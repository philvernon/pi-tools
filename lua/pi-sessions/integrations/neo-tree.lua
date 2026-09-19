local core = require("pi-sessions")
local renderer = require("neo-tree.ui.renderer")
local common = require("neo-tree.sources.common.components")
local commands = require("neo-tree.sources.common.commands")

local components = vim.tbl_extend("force", {}, common, {
	session = function(_, node, _, width)
		local title = node.extra.session.title
		local time = node.extra.session.time
		local available = math.max(1, width - #time - 2)
		if vim.api.nvim_strwidth(title) > available then
			title = vim.fn.strcharpart(title, 0, math.max(0, available - 1)) .. "…"
		end
		local gap = math.max(2, width - vim.api.nvim_strwidth(title) - #time)
		return {
			{ text = title, highlight = "Normal" },
			{ text = string.rep(" ", gap) .. time, highlight = "Comment" },
		}
	end,
})

local M = {
	name = "pi_sessions",
	display_name = "  Pi ",
	components = components,
}

local preview_sessions = {}
local preview_group = vim.api.nvim_create_augroup("PiSessionsPreview", { clear = true })

vim.api.nvim_create_autocmd("BufReadCmd", {
	group = preview_group,
	pattern = "pi-session://*",
	callback = function(args)
		local session = preview_sessions[vim.api.nvim_buf_get_name(args.buf)]
		if not session then
			return
		end
		vim.api.nvim_buf_set_lines(args.buf, 0, -1, false, core.preview(session))
		vim.bo[args.buf].modified = false
		vim.bo[args.buf].modifiable = false
	end,
})

local function redraw(state)
	renderer.redraw(state)
end

M.commands = {
	open = function(state)
		local node = state.tree:get_node()
		if not node then
			return
		end
		if node.type == "session" then
			local win = require("neo-tree").get_prior_window()
			if state.current_position == "float" then
				renderer.close(state)
			end
			core.resume(node.extra.session, win)
		elseif node.type == "project" then
			if node:is_expanded() then
				node:collapse()
			else
				node:expand()
			end
			redraw(state)
		end
	end,
	collapse = function(state)
		local node = state.tree:get_node()
		if not node then
			return
		end

		if node.type == "project" then
			if node:is_expanded() then
				node:collapse()
				redraw(state)
			end
			return
		end

		local parent = state.tree:get_node(node:get_parent_id())
		if parent and parent.type == "project" then
			parent:collapse()
			redraw(state)
			renderer.focus_node(state, parent:get_id())
		end
	end,
	new = function(state)
		local node = state.tree:get_node()
		if not node then
			return
		end
		local project = node.extra and node.extra.project
		if project then
			local win = require("neo-tree").get_prior_window()
			if state.current_position == "float" then
				renderer.close(state)
			end
			core.new(project, win)
		end
	end,
	refresh = function(state)
		M.navigate(state)
	end,
}

commands._add_common_commands(M.commands)

M.default_config = {
	window = {
		position = "float",
		mappings = {
			["<cr>"] = "open",
			["l"] = "open",
			["h"] = "collapse",
			["o"] = "collapse",
			["n"] = "new",
			["R"] = "refresh",
		},
	},
	renderers = {
		project = {
			{ "indent", with_expanders = true },
			{ "name", highlight = "NeoTreeDirectoryName" },
		},
		session = {
			{ "indent" },
			{ "session" },
		},
	},
}

function M.navigate(state, _, _, callback)
	local snapshot = core.scan()
	local cwd = vim.fs.normalize(vim.uv.cwd())
	local nodes = {}
	preview_sessions = {}
	state.default_expanded_nodes = {}

	for _, project in ipairs(snapshot.projects) do
		local project_id = "project:" .. project.cwd
		local children = {}
		for _, session in ipairs(project.sessions) do
			local preview_path = "pi-session://" .. session.id
			preview_sessions[preview_path] = session
			children[#children + 1] = {
				id = session.path,
				path = preview_path,
				name = session.label,
				type = "session",
				loaded = true,
				extra = { session = session, project = project },
			}
		end
		nodes[#nodes + 1] = {
			id = project_id,
			name = project.name,
			type = "project",
			loaded = true,
			children = children,
			extra = { project = project },
		}
		if vim.fs.normalize(project.cwd) == cwd then
			state.default_expanded_nodes[#state.default_expanded_nodes + 1] = project_id
		end
	end

	state.path = core.root()
	renderer.show_nodes(nodes, state)
	if callback then
		vim.schedule(callback)
	end
end

function M.setup() end

function M.open()
	require("neo-tree.command").execute({
		action = "focus",
		source = M.name,
		position = "float",
	})
end

function M.focus_or_open()
	local state = require("neo-tree.sources.manager").get_state(M.name)
	if state and state.winid and vim.api.nvim_win_is_valid(state.winid) then
		vim.api.nvim_set_current_win(state.winid)
		return
	end

	require("neo-tree.command").execute({
		action = "focus",
		source = M.name,
		position = "left",
	})
end

function M.toggle()
	require("neo-tree.command").execute({
		source = M.name,
		toggle = true,
	})
end

return M
