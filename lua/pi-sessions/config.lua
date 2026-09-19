local M = {}

local module_path = debug.getinfo(1, "S").source:gsub("^@", "")
local plugin_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(module_path)))

local defaults = {
	root = nil,
	integration = "neo-tree",
	commands = {
		browser = "PiSessionBrowser",
		browser_aliases = { "PiSesh" },
		client = "PiClient",
	},
	keymaps = {
		picker = "<leader>aa",
	},
	sidekick = {
		enabled = true,
		tmux_path = vim.fs.joinpath(plugin_root, "bin"),
		tool = {
			cmd = { "pi", "--tui-mode", "fullscreen" },
			native_scroll = true,
		},
		keys = {
			search_pi_sessions = {
				"<c-r>",
				"picker",
				mode = "n",
				desc = "Pi session picker",
			},
			host_session_picker = {
				",p",
				"picker",
				mode = "t",
				desc = "Pi session picker",
			},
			host_session_tree = {
				",e",
				"tree",
				mode = "t",
				desc = "Pi session tree",
			},
			host_new_pi = {
				",n",
				"new",
				mode = "t",
				desc = "New Pi",
			},
		},
	},
	telescope = {
		decorate_sidekick = true,
	},
}

local config = vim.deepcopy(defaults)

function M.setup(opts)
	config = vim.tbl_deep_extend("force", {}, vim.deepcopy(defaults), opts or {})
	return config
end

function M.get()
	return config
end

function M.root()
	if config.root and config.root ~= "" then
		return vim.fs.normalize(vim.fn.expand(config.root))
	end
	return vim.fs.normalize(vim.env.PI_CODING_AGENT_SESSION_DIR or vim.fn.expand("~/.pi/agent/sessions"))
end

return M
