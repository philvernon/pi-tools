local M = {}

local cache = {}

local function content_text(content)
	if type(content) == "string" then
		return content
	end
	if type(content) ~= "table" then
		return
	end

	local parts = {}
	for _, part in ipairs(content) do
		if type(part) == "table" and part.type == "text" and type(part.text) == "string" then
			parts[#parts + 1] = part.text
		end
	end
	return #parts > 0 and table.concat(parts, "\n") or nil
end

local function add(lines, body, quote)
	if not body or body == "" then
		return
	end
	for _, line in ipairs(vim.split(vim.trim(body), "\n", { plain = true })) do
		lines[#lines + 1] = quote and ("> " .. line) or line
	end
	lines[#lines + 1] = ""
end

local function render_entry(lines, entry)
	if entry.type == "compaction" then
		add(lines, "## Summary\n" .. (entry.summary or ""))
		return
	elseif entry.type == "branch_summary" then
		add(lines, "## Branch summary\n" .. (entry.summary or ""))
		return
	elseif entry.type ~= "message" or type(entry.message) ~= "table" then
		return
	end

	local message = entry.message
	if message.role == "user" then
		add(lines, content_text(message.content), true)
	elseif message.role == "assistant" then
		add(lines, content_text(message.content))
		if type(message.content) == "table" then
			for _, part in ipairs(message.content) do
				if type(part) == "table" and (part.type == "toolCall" or part.type == "tool_call") then
					local args = part.arguments or part.input
					local detail = type(args) == "table" and (args.path or args.file_path or args.command or args.query)
						or nil
					add(
						lines,
						("### Tool: %s%s"):format(
							part.name or part.toolName or "unknown",
							detail and (" " .. tostring(detail)) or ""
						)
					)
				end
			end
		end
	elseif message.role == "toolResult" and message.isError then
		add(
			lines,
			("### Tool error: %s\n%s"):format(message.toolName or "unknown", content_text(message.content) or "")
		)
	elseif message.role == "bashExecution" then
		add(lines, "### Tool: bash " .. (message.command or ""))
	elseif message.role == "branchSummary" then
		add(lines, "## Branch summary\n" .. (message.summary or ""))
	elseif message.role == "compactionSummary" then
		add(lines, "## Summary\n" .. (message.summary or ""))
	end
end

function M.render(session)
	local stat = vim.uv.fs_stat(session.path)
	if not stat then
		return { "Session file not found" }
	end

	local key = ("%d:%d:%d"):format(stat.size, stat.mtime.sec, stat.mtime.nsec)
	local cached = cache[session.path]
	if cached and cached.key == key then
		return cached.lines
	end

	local file = io.open(session.path, "r")
	if not file then
		return { "Unable to read session" }
	end

	local header, leaf
	local entries, ordered = {}, {}
	for line in file:lines() do
		local ok, entry = pcall(vim.json.decode, line)
		if ok and type(entry) == "table" then
			if entry.type == "session" then
				header = entry
			elseif entry.id then
				entries[entry.id] = entry
				ordered[#ordered + 1] = entry
				leaf = entry
			end
		end
	end
	file:close()

	local branch = {}
	if header and header.version == 1 then
		branch = ordered
	else
		local seen = {}
		while leaf and leaf.id and not seen[leaf.id] do
			seen[leaf.id] = true
			branch[#branch + 1] = leaf
			leaf = leaf.parentId and entries[leaf.parentId] or nil
		end
		for i = 1, math.floor(#branch / 2) do
			branch[i], branch[#branch - i + 1] = branch[#branch - i + 1], branch[i]
		end
	end

	local lines = {}
	for _, entry in ipairs(branch) do
		render_entry(lines, entry)
	end
	if #lines == 0 then
		lines = { "No previewable messages" }
	elseif #lines > 500 then
		lines = vim.list_slice(lines, #lines - 498, #lines)
		table.insert(lines, 1, "> … older preview omitted")
	end

	cache[session.path] = { key = key, lines = lines }
	return lines
end

function M.lines(session)
	return M.render(session)
end

return M
