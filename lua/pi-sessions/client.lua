local M = {}

function M.open()
	local cwd = vim.uv.cwd()
	local buf = vim.api.nvim_get_current_buf()
	local empty = vim.tbl_count(vim.api.nvim_tabpage_list_wins(0)) == 1
		and vim.api.nvim_buf_get_name(buf) == ""
		and vim.bo[buf].buftype == ""
		and not vim.bo[buf].modified

	if not empty then
		vim.cmd.tabnew()
	end

	local client_win = vim.api.nvim_get_current_win()

	require("pi-sessions.sidekick").set_client_window(client_win)
	require("pi-sessions").new(cwd)

	require("neo-tree.command").execute({
		action = "focus",
		source = "pi_sessions",
		position = "left",
	})

	if vim.api.nvim_win_is_valid(client_win) then
		vim.api.nvim_set_current_win(client_win)
	end
end

return M
