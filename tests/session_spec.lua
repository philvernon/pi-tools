local root = vim.fs.joinpath(vim.fn.getcwd(), "tests", "fixtures")

require("pi-sessions.config").setup({ root = root })
local Sessions = require("pi-sessions.sessions")

local snapshot = Sessions.scan()
assert(#snapshot.sessions == 2, ("expected 2 sessions, got %d"):format(#snapshot.sessions))
assert(#snapshot.projects == 2, ("expected 2 projects, got %d"):format(#snapshot.projects))

local by_id = {}
for _, session in ipairs(snapshot.sessions) do
	by_id[session.id] = session
end

assert(by_id["session-v1"], "missing v1 session")
assert(by_id["session-v1"].title == "First prompt from v1", "v1 title should come from first user message")
assert(by_id["session-v1"].version == 1, "v1 version should be preserved")

assert(by_id["session-v3"], "missing v3 session")
assert(by_id["session-v3"].title == "Named v3 session", "session_info name should override first user message")
assert(by_id["session-v3"].version == 3, "v3 version should be preserved")

local project_sessions = Sessions.for_project("/tmp/pi-sessions/project-v3")
assert(#project_sessions == 1 and project_sessions[1].id == "session-v3", "project lookup failed")

local preview = require("pi-sessions.preview").lines(by_id["session-v3"])
local rendered = table.concat(preview, "\n")
assert(rendered:find("First prompt from v3", 1, true), "v3 preview should include the active branch user message")
assert(rendered:find("response", 1, true), "v3 preview should include the active branch assistant message")

local Sidekick = require("pi-sessions.sidekick")
local picker_opts = require("pi-sessions.integrations.telescope").sidekick_cli_opts()
local indexed = picker_opts.make_indexed({
	{
		tool = { name = "pi" },
		session = { mux_session = Sidekick.tool_name("session-v3") .. " x" },
	},
})
assert(indexed[1].display:find("Named v3 session", 1, true), "Sidekick picker should decorate persisted Pi sessions")

print("pi-sessions session tests: ok")
