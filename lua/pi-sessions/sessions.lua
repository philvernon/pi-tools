local Config = require("pi-sessions.config")

local M = {}

local function timestamp(ts)
	if not ts or ts == "" then
		return "unknown"
	end
	local date, time = ts:match("^(%d%d%d%d%-%d%d%-%d%d)T(%d%d:%d%d)")
	return date and (date .. " " .. time) or ts
end

local function message_text(message)
	if type(message) ~= "table" or message.role ~= "user" then
		return
	end
	if type(message.content) == "string" then
		return message.content
	end
	if type(message.content) == "table" then
		local text = {}
		for _, part in ipairs(message.content) do
			if type(part) == "table" and part.type == "text" and type(part.text) == "string" then
				text[#text + 1] = part.text
			end
		end
		return table.concat(text, " ")
	end
end

function M.read(path)
	local file = io.open(path, "r")
	if not file then
		return
	end

	local header, name, first_message
	for line in file:lines() do
		if not header or not first_message or line:find('"session_info"', 1, true) then
			local ok, item = pcall(vim.json.decode, line)
			if ok and type(item) == "table" then
				if not header and item.type == "session" then
					header = item
				elseif item.type == "session_info" then
					name = type(item.name) == "string" and vim.trim(item.name) or nil
					if name == "" then
						name = nil
					end
				elseif not first_message and item.type == "message" then
					first_message = message_text(item.message)
				end
			end
		end
	end
	file:close()

	if not header or not header.cwd or not header.id then
		return
	end

	name = name or first_message
	if name then
		name = name:gsub("%s+", " ")
	end

	local session = {
		id = header.id,
		path = path,
		cwd = vim.fs.normalize(header.cwd),
		timestamp = header.timestamp,
		time = timestamp(header.timestamp),
		name = name,
		version = header.version,
	}
	session.title = name or header.id:sub(1, 8)
	session.label = ("%s  %s"):format(session.title, session.time)
	return session
end

function M.scan()
	local sessions = {}
	local root = Config.root()

	if vim.uv.fs_stat(root) then
		for _, path in ipairs(vim.fn.globpath(root, "**/*.jsonl", false, true)) do
			local session = M.read(path)
			if session then
				sessions[#sessions + 1] = session
			end
		end
	end

	table.sort(sessions, function(a, b)
		return (a.timestamp or "") > (b.timestamp or "")
	end)

	local by_cwd, projects = {}, {}
	for _, session in ipairs(sessions) do
		local project = by_cwd[session.cwd]
		if not project then
			project = {
				cwd = session.cwd,
				name = vim.fn.fnamemodify(session.cwd, ":~"),
				sessions = {},
			}
			by_cwd[session.cwd] = project
			projects[#projects + 1] = project
		end
		project.sessions[#project.sessions + 1] = session
	end

	return { sessions = sessions, projects = projects }
end

function M.all()
	return M.scan().sessions
end

function M.projects()
	return M.scan().projects
end

function M.for_project(project)
	local cwd = type(project) == "table" and project.cwd or project
	cwd = cwd and vim.fs.normalize(cwd) or cwd

	for _, item in ipairs(M.scan().projects) do
		if item.cwd == cwd then
			return item.sessions
		end
	end
	return {}
end

return M
