# pi-tools

Persistent Pi CLI and Neovim tooling built around a dedicated `tmux -L agents` server.

## Layout

```text
pi-tools/
├── bin/
│   ├── pia
│   └── tmux
├── extensions/
│   └── tmux-session-rename.ts
├── lua/
│   ├── pi-sessions/
│   └── neo-tree/
├── tests/
└── README.md
```

The repository root is a valid Neovim plugin, so lazy.nvim can install the repo directly. The `bin/` directory contains the CLI side of the same session/process workflow. The `extensions/` directory contains Pi extensions loaded directly from this repo.

## Pi extensions

Pi can load this repo as a local package:

```json
{
  "source": "/path/to/pi-tools",
  "extensions": [
    "+extensions/tmux-session-rename.ts"
  ]
}
```

`tmux-session-rename.ts` renames Pi sessions running inside tmux to `pi-<session-id>` so CLI and Neovim session discovery can reconnect to them consistently.

## CLI

### `pia`

`pia` launches Pi inside the dedicated `agents` tmux server. When invoked with `-c` or `--continue`, it attempts to attach to the already-running tmux session corresponding to the latest Pi session for the current working directory before starting a new process. `pia --detach` (or `pia -d`) starts a new session without attaching and prints its tmux session ID.

Install it somewhere already on your shell PATH, for example:

```sh
ln -sfn /path/to/pi-tools/bin/pia ~/.local/bin/pia
```

### `bin/tmux`

This is the tmux shim used by the Neovim/Sidekick integration. It directs Sidekick's tmux commands to the dedicated `agents` tmux server rather than the normal tmux server.

## Neovim

The Neovim module is `pi-sessions`. It provides:

- Pi JSONL session discovery and metadata
- transcript previews
- persisted-session resume and new-session launch through Sidekick
- embedding Sidekick terminals into existing Neovim windows
- Telescope session picker
- Neo-tree session source
- Pi-specific Sidekick terminal mappings
- Sidekick picker decoration with Pi session titles

It intentionally does not replace `pi-nvim`, which handles editor-to-Pi context transport.

### lazy.nvim

Because the plugin runtime is at the repository root, the GitHub repo can be installed directly:

```lua
{
  "philvernon/pi-tools",
  main = "pi-sessions",
  lazy = false,
  opts = {
    integration = "neo-tree",
  },
}
```

For local development:

```lua
{
  dir = vim.fn.expand("~/dev-trash/pi-tools"),
  name = "pi-tools",
  main = "pi-sessions",
  lazy = false,
  opts = {
    integration = "neo-tree",
  },
}
```

The plugin automatically prepends its own `bin/` directory to Neovim's PATH for Sidekick, so no separate `agent-tmux` config path is required.

### Requirements

- Neovim
- Pi
- [folke/sidekick.nvim](https://github.com/folke/sidekick.nvim)
- Telescope for the picker
- Neo-tree for the persistent session browser
- tmux

Telescope and Neo-tree are optional if their integrations are not used.

### Commands

- `:PiSessionBrowser [neo-tree|telescope]`
- `:PiSesh [neo-tree|telescope]` — compatibility alias
- `:PiClient`

The default normal-mode picker mapping is `<leader>aa`.

The plugin deliberately does not define `:PiSessions` because `pi-nvim` owns that command.

### Sidekick integration

Pi is configured as:

```text
pi --tui-mode fullscreen
```

Default Pi-specific Sidekick mappings:

- `<C-r>` in terminal normal mode: Pi session picker
- `,p` in terminal mode: Pi session picker
- `,e` in terminal mode: Pi session tree
- `,n` in terminal mode: new Pi session

The Sidekick compatibility patches needed for persisted tmux attachment and caller-selected Neovim windows are isolated in `lua/pi-sessions/sidekick.lua`.

## Tests

```sh
nvim --headless -u tests/minimal_init.lua -l tests/session_spec.lua
```

The fixtures cover legacy v1 sessions, current tree-style sessions, previews and Sidekick picker session-title decoration.
