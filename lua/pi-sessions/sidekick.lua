local M = {}

local tool_prefix = "pi-s-"
local active_window
local terminal_patched = false
local tmux_patched = false

local function valid_window(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function client_window()
	local win = vim.t.pi_sessions_client_win
	return valid_window(win) and win or nil
end

local function prepend_path(path)
	if not path or path == "" then
		return
	end

	path = vim.fs.normalize(vim.fn.expand(path))
	local entries = vim.split(vim.env.PATH or "", ":", { plain = true })
	if not vim.tbl_contains(entries, path) then
		vim.env.PATH = path .. ":" .. (vim.env.PATH or "")
	end
end

function M.tool_name(id)
	return tool_prefix .. vim.fn.sha256(id):sub(1, 10)
end

local function restore_window(terminal)
	local win = terminal.win
	if valid_window(win) and vim.api.nvim_win_get_buf(win) == terminal.buf then
		local previous = terminal._pi_sessions_previous_buf
		if not previous or not vim.api.nvim_buf_is_valid(previous) or previous == terminal.buf then
			previous = vim.api.nvim_create_buf(true, false)
		end
		if vim.api.nvim_get_current_win() == win then
			vim.cmd.stopinsert()
		end
		vim.api.nvim_win_set_buf(win, previous)
	end

	if valid_window(win) and vim.w[win].sidekick_session_id == terminal.id then
		vim.w[win].sidekick_cli = nil
		vim.w[win].sidekick_session_id = nil
	end

	terminal.win = nil
	terminal._pi_sessions_embedded = nil
	terminal._pi_sessions_previous_buf = nil
end

local function patch_tmux_attach()
	if tmux_patched then
		return
	end

	local Tmux = require("sidekick.cli.session.tmux")
	assert(type(Tmux.attach) == "function", "unsupported Sidekick tmux backend")

	tmux_patched = true
	local attach = Tmux.attach

	function Tmux:attach()
		local mux = self.mux_session

		if self.tool and self.tool.name == "pi" and type(mux) == "string" then
			return {
				cmd = { "tmux", "attach-session", "-t", mux },
			}
		end

		return attach(self)
	end
end

local function patch_terminal()
	if terminal_patched then
		return
	end

	local Terminal = require("sidekick.cli.terminal")
	assert(type(Terminal.open_win) == "function", "unsupported Sidekick terminal backend")
	assert(type(Terminal.hide) == "function", "unsupported Sidekick terminal backend")
	assert(type(Terminal.wo) == "function", "unsupported Sidekick terminal backend")

	terminal_patched = true
	local open_win = Terminal.open_win
	local hide = Terminal.hide
	local wo = Terminal.wo

	function Terminal:open_win()
		local target = active_window
		if not valid_window(target) then
			return open_win(self)
		end
		if not self.buf then
			return
		end
		if self.win == target and vim.api.nvim_win_get_buf(target) == self.buf then
			return
		end

		if self._pi_sessions_embedded and self.win ~= target then
			self:hide()
			if not valid_window(target) then
				return open_win(self)
			end
		end

		local current_id = vim.w[target].sidekick_session_id
		if current_id and current_id ~= self.id then
			local current = Terminal.get(current_id)
			if current then
				current:hide()
				if not valid_window(target) then
					return open_win(self)
				end
			end
		end

		self._pi_sessions_previous_buf = vim.api.nvim_win_get_buf(target)
		self._pi_sessions_embedded = true
		self.win = target

		vim.api.nvim_win_set_buf(target, self.buf)
		vim.w[target].sidekick_cli = self.tool
		vim.w[target].sidekick_session_id = self.id
	end

	function Terminal:wo(opts)
		if not self._pi_sessions_embedded then
			return wo(self, opts)
		end
	end

	function Terminal:hide()
		if self._pi_sessions_embedded then
			restore_window(self)
			return self
		end
		return hide(self)
	end
end

local function with_window(win, fn)
	patch_tmux_attach()
	patch_terminal()

	local previous = active_window
	active_window = valid_window(win) and win or client_window()

	local result = { pcall(fn) }
	active_window = previous

	if not result[1] then
		error(result[2], 0)
	end

	return unpack(result, 2)
end

local function attached_pi(State, name)
	if not name then
		return
	end

	for _, state in ipairs(State.get({ attached = true })) do
		if state.tool and state.tool.name == name then
			return state
		end
	end
end

local function launch(cwd, args, name, win)
	return with_window(win, function()
		local Config = require("sidekick.config")
		local Session = require("sidekick.cli.session")
		local State = require("sidekick.cli.state")

		Session.setup()

		local tool = Config.get_tool("pi")
		local cmd = vim.deepcopy(tool.cmd)
		vim.list_extend(cmd, args or {})
		tool = tool:clone({ cmd = cmd, name = name or tool.name })

		local attached = attached_pi(State, name)
		if attached then
			return State.attach(attached, { show = true, focus = true })
		end

		local session = Session.new({
			tool = tool,
			cwd = cwd,
		})

		return State.attach(State.get_state(session), { show = true, focus = true })
	end)
end

local actions = {
	picker = function()
		require("pi-sessions.integrations.telescope").open()
	end,
	tree = function()
		require("pi-sessions.integrations.neo-tree").focus_or_open()
	end,
	new = function()
		require("pi-sessions").new(vim.uv.cwd(), vim.api.nvim_get_current_win())
	end,
}

local function configure_sidekick()
	local opts = require("pi-sessions.config").get().sidekick
	if not opts.enabled then
		return
	end

	prepend_path(opts.tmux_path)

	local Config = require("sidekick.config")
	Config.cli.tools.pi =
		vim.tbl_deep_extend("force", {}, vim.deepcopy(Config.cli.tools.pi or {}), vim.deepcopy(opts.tool or {}))

	for name, spec in pairs(opts.keys or {}) do
		if spec == false then
			Config.cli.win.keys[name] = false
		else
			local keymap = vim.deepcopy(spec)
			local action = keymap[2]
			if type(action) == "string" and actions[action] then
				keymap[2] = actions[action]
			end
			Config.cli.win.keys[name] = keymap
		end
	end
end

function M.setup()
	local opts = require("pi-sessions.config").get().sidekick
	if not opts.enabled then
		return
	end

	configure_sidekick()
	patch_tmux_attach()
end

function M.set_client_window(win)
	assert(valid_window(win), "invalid PiClient window")
	vim.t.pi_sessions_client_win = win
end

function M.resume(session, win)
	return launch(session.cwd, { "--session", session.path }, M.tool_name(session.id), win)
end

function M.new(cwd, win)
	local id = vim.fn.sha256(("%s:%s"):format(cwd, vim.uv.hrtime())):sub(1, 10)
	return launch(cwd, {}, "pi-new-" .. id, win)
end

return M
