local M = {}

local function session_titles()
	local titles = {}
	local Sidekick = require("pi-sessions.sidekick")

	for _, session in ipairs(require("pi-sessions").all()) do
		titles[Sidekick.tool_name(session.id)] = session.title
		titles["pi-" .. session.id] = session.title
	end

	return titles
end

function M.sidekick_cli_opts()
	return {
		make_indexed = function(items)
			local titles = session_titles()
			local indexed = {}

			for idx, state in ipairs(items) do
				local mux = state.session and state.session.mux_session
				local display = mux or (state.tool and state.tool.name) or tostring(state)
				local title

				if state.tool then
					title = titles[state.tool.name]
				end

				if not title and type(mux) == "string" then
					for prefix, candidate in pairs(titles) do
						if mux:sub(1, #prefix) == prefix then
							title = candidate
							break
						end
					end
				end

				if title then
					display = display .. "  " .. title
				end

				indexed[#indexed + 1] = {
					idx = idx,
					text = state,
					display = display,
				}
			end

			return indexed
		end,

		make_display = function()
			return function(entry)
				return entry.value.display
			end
		end,

		make_ordinal = function(entry)
			return entry.display
		end,
	}
end

function M.setup()
	local opts = require("pi-sessions.config").get().telescope
	if not opts.decorate_sidekick then
		return
	end

	if type(_G.__TelescopeUISelectSpecificOpts) == "table" then
		_G.__TelescopeUISelectSpecificOpts.sidekick_cli = M.sidekick_cli_opts()
	end
end

function M.open()
	local core = require("pi-sessions")
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local conf = require("telescope.config").values
	local entry_display = require("telescope.pickers.entry_display")
	local finders = require("telescope.finders")
	local pickers = require("telescope.pickers")
	local previewers = require("telescope.previewers")

	local rows = {}
	for _, project in ipairs(core.scan().projects) do
		for _, session in ipairs(project.sessions) do
			rows[#rows + 1] = { project = project, session = session }
		end
	end

	local displayer = entry_display.create({
		separator = "  ",
		items = {
			{ width = 30 },
			{ remaining = true },
			{ width = 16 },
		},
	})

	pickers
		.new({}, {
			prompt_title = "Pi sessions",
			finder = finders.new_table({
				results = rows,
				entry_maker = function(row)
					return {
						value = row,
						display = function()
							return displayer({
								{ row.project.name, "Directory" },
								{ row.session.title, "Normal" },
								{ row.session.time, "Comment" },
							})
						end,
						ordinal = table.concat({
							row.project.cwd,
							row.session.name or "",
							row.session.timestamp or "",
						}, " "),
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = previewers.new_buffer_previewer({
				define_preview = function(self, entry)
					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, core.preview(entry.value.session))
					vim.bo[self.state.bufnr].filetype = "markdown"
					vim.schedule(function()
						if self.state.winid and vim.api.nvim_win_is_valid(self.state.winid) then
							vim.api.nvim_win_set_cursor(
								self.state.winid,
								{ vim.api.nvim_buf_line_count(self.state.bufnr), 0 }
							)
						end
					end)
				end,
			}),
			attach_mappings = function(bufnr, map)
				local function selected()
					local entry = action_state.get_selected_entry()
					return entry and entry.value
				end

				local function target_window()
					return action_state.get_current_picker(bufnr).original_win_id
				end

				actions.select_default:replace(function()
					local row = selected()
					if row then
						local win = target_window()
						actions.close(bufnr)
						core.resume(row.session, win)
					end
				end)

				local function new()
					local row = selected()
					if row then
						local win = target_window()
						actions.close(bufnr)
						core.new(row.project, win)
					end
				end

				map("i", "<C-n>", new)
				map("n", "n", new)
				return true
			end,
		})
		:find()
end

return M
