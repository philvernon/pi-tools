# Subagents Plan

## Design

Use the terminal as the orchestration substrate: every Pi agent runs in the shared `agents` tmux server, `pia` is the agent-facing launch command, and no backend-specific orchestration layer is required.

## Implementation

1. Add `extensions/pia-subagents/index.ts` with one `pia_subagent` tool.
2. Invoke `pia --detach`; the extension must not create tmux sessions itself. `pia` owns detached launch and returns the stable session handle.
3. Create the child session through Pi's `SessionManager` with the current session as `parentSession`; materialize that header at the exact session path and pass `--session <path>` to the Pi process so SDK identity and the tmux worker share one transcript.
4. Pass provider, model, cwd, and task data explicitly; normalize paths to absolute paths so literal names such as `@stories` are not misinterpreted.
5. Use the returned handle for ordinary tmux observation and lifecycle commands; do not hide tmux behind another manager.
6. Let the parent agent make multiple tool calls for parallel work; return the handle immediately for detached tasks.
7. Support `wait: true` through `pia --detach --wait`: keep the worker in the shared tmux server, duplicate its output to durable per-run `output.log`, write authoritative `result.json` and `status.json`, and follow lifecycle state without attaching.
8. Test with an isolated tmux socket: verify `pia` invocation, model/provider forwarding, cwd/path handling, child session identity, detached handles, wait-mode streaming, completion, and cleanup of only test sessions.
