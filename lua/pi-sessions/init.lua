local Config = require("pi-sessions.config")
local Sessions = require("pi-sessions.sessions")

local M = {}

local integrations_group = vim.api.nvim_create_augroup("PiSessionsIntegrations", { clear = true })

local function setup_integration(plugin, probe, module)
	local function run()
		local ok, integration = pcall(require, module)
		if ok and type(integration.setup) == "function" then
			integration.setup()
		end
	end

	if package.loaded[probe] or package.loaded[module] then
		vim.schedule(run)
	end

	vim.api.nvim_create_autocmd("User", {
		group = integrations_group,
		pattern = "LazyLoad",
		callback = function(args)
			if args.data == plugin then
				vim.schedule(run)
			end
		end,
	})
end

function M.root()
	return Config.root()
end

function M.scan()
	return Sessions.scan()
end

function M.all()
	return Sessions.all()
end

function M.projects()
	return Sessions.projects()
end

function M.sessions(project)
	return Sessions.for_project(project)
end

function M.preview(session)
	return require("pi-sessions.preview").lines(session)
end

function M.resume(session, win)
	assert(session and session.id and session.path and session.cwd, "invalid Pi session")
	return require("pi-sessions.sidekick").resume(session, win)
end

function M.new(project, win)
	local cwd = type(project) == "table" and project.cwd or project
	assert(cwd and cwd ~= "", "invalid Pi project")
	return require("pi-sessions.sidekick").new(cwd, win)
end

function M.open(integration)
	integration = integration or Config.get().integration
	if integration == "neotree" then
		integration = "neo-tree"
	end
	return require("pi-sessions.integrations." .. integration).open()
end

function M.setup(opts)
	local config = Config.setup(opts)

	local function create_browser_command(name)
		if not name or name == "" then
			return
		end
		vim.api.nvim_create_user_command(name, function(cmd)
			M.open(cmd.args ~= "" and cmd.args or nil)
		end, {
			nargs = "?",
			force = true,
			complete = function()
				return { "neo-tree", "telescope" }
			end,
		})
	end

	create_browser_command(config.commands.browser)
	for _, alias in ipairs(config.commands.browser_aliases or {}) do
		create_browser_command(alias)
	end

	if config.commands.client and config.commands.client ~= "" then
		vim.api.nvim_create_user_command(config.commands.client, function()
			require("pi-sessions.client").open()
		end, { force = true })
	end

	if config.keymaps.picker and config.keymaps.picker ~= "" then
		vim.keymap.set("n", config.keymaps.picker, function()
			require("pi-sessions.integrations.telescope").open()
		end, { desc = "Session picker" })
	end

	setup_integration("sidekick.nvim", "sidekick", "pi-sessions.sidekick")
	setup_integration("telescope.nvim", "telescope", "pi-sessions.integrations.telescope")

	return config
end

return M
