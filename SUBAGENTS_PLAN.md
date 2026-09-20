# Subagents Plan

## Design

Use the terminal as the orchestration substrate: every Pi agent runs in the shared `agents` tmux server, `pia` is the agent-facing launch command, and no backend-specific orchestration layer is required.

## Implementation

1. Add `extensions/pia-subagents/index.ts` with one `pia_subagent` tool.
2. Invoke `pia --detach`; the extension must not create tmux sessions itself. `pia` owns detached launch and returns the stable session handle.
3. Pass provider, model, cwd, and task data explicitly; normalize paths to absolute paths so literal names such as `@stories` are not misinterpreted.
4. Use the returned handle for ordinary tmux observation and lifecycle commands; do not hide tmux behind another manager.
5. Let the parent agent make multiple tool calls for parallel work; return the handle immediately for each task.
6. Test with an isolated tmux socket: verify `pia` invocation, model/provider forwarding, cwd/path handling, completion, and cleanup of only test sessions.
