<div align="center">

<img src="assets/logo.svg" alt="Seashell logo" width="200"/>

# SeaShell

**Talk to Claude from any terminal block. Get answers back. Even when you're not at your chat.**

An MCP server that brings Claude into [Wave Terminal](https://github.com/wavetermdev/waveterm) — execute commands, manage Wave configuration, control terminal blocks, and exchange asynchronous messages with Claude from any block, with optional autonomous responses via a small daemon.

[Quick start](#quick-start) · [Inbox feature](#talk-to-claude-from-anywhere) · [Features](#features) · [Customize via AI](#customize-via-ai) · [Architecture](docs/ARCHITECTURE.md)

</div>

---

## What it is

Seashell is a [Model Context Protocol](https://modelcontextprotocol.io) (MCP) server, written in Swift, that runs alongside Claude Desktop on macOS. It gives Claude tools to:

- 📨 **Receive notes you leave from any terminal block** (via `seashell-msg`) and **reply back to your blocking commands** (`seashell-ask`) — see [Talk to Claude from anywhere](#talk-to-claude-from-anywhere)
- ⚙️ **Read and write Wave Terminal's JSON configs** — settings, widgets, AI presets, backgrounds
- 🧱 **Create, delete, and query Wave blocks** via an in-Wave helper
- 🔐 **Manage Wave secrets**, themes, fish widget definitions, and workspace bootstrapping
- ▶️ **Execute shell commands** (silently or visible in Wave blocks), with intelligent output capture

A small fish/Ollama starter and an autonomous daemon are bundled as **opt-in extras** in `examples/`. Seashell itself doesn't require either.

## Quick start

```bash
# 1. Build
git clone https://github.com/M-Pineapple/seashell ~/Github/seashell
cd ~/Github/seashell && ./build.sh

# 2. Register with Claude Desktop
# Edit ~/Library/Application\ Support/Claude/claude_desktop_config.json:
#
#   "mcpServers": {
#     "seashell": {
#       "command": "/absolute/path/to/seashell/.build/release/seashell",
#       "args": ["--port", "9876"]
#     }
#   }
#
# Then restart Claude Desktop.

# 3. (Optional) Install the bin/ commands so you can talk to Claude from any terminal
cp examples/wave-config/bin/seashell-{msg,ask,init} ~/.local/bin/
chmod +x ~/.local/bin/seashell-*

# 4. Try it — leave a note from any terminal:
seashell-msg "What's the weather in our build pipeline?"
# Then in Claude Desktop chat, type "?" — Claude will pick up the note and respond.
```

For the **autonomous** experience (Claude responds even without you typing in chat), see [the daemon](#the-daemon-truly-autonomous).

## Talk to Claude from anywhere

This is Seashell's marquee feature. From any Wave Terminal block (or any shell), leave Claude a note or ask a blocking question — Claude picks it up and responds via the MCP tools.

### `seashell-msg` — fire-and-forget notes

```bash
seashell-msg "compare the test output to what we just discussed"
swift build 2>&1 | seashell-msg "fix these errors"
seashell-msg --file /tmp/build.log "investigate this"
```

The note is appended to the project's `.seashell-inbox/inbox.jsonl` (created by `seashell-init`) or the global `~/.seashell/inbox.jsonl`. Next time you message Claude — even just `?` — Claude calls `read_user_inbox`, sees your note, and responds in chat.

### `seashell-ask` — blocking questions

```bash
seashell-ask "what's the status of the refactoring?"
# ⏳ Waiting for Claude to respond (timeout: 600s)..............
# (when Claude replies via reply_to_user, this prints the answer and exits)
```

Same as `seashell-msg` but the note carries a `reply_token` and the shell command **blocks**, polling for a matching reply in `replies.jsonl`. When Claude calls `reply_to_user`, your terminal unblocks with the answer.

### `seashell-init` — register a project

```bash
cd ~/Github/my-project
seashell-init
# ✓ Created .seashell-inbox/
# ✓ Registered my-project in ~/.seashell/projects.jsonl
# ✓ Created CLAUDE.md with Seashell inbox hint
```

`seashell-msg` walks up from `$PWD` to find the nearest `.seashell-inbox/` ancestor. Each project gets its own inbox so messages route correctly when you have multiple Claude conversations open. Without `seashell-init`, notes go to the global inbox.

### How routing works

```
$ cd ~/Github/refactoring-project
$ seashell-msg "..."   →  ~/Github/refactoring-project/.seashell-inbox/inbox.jsonl

$ cd /tmp/random
$ seashell-msg "..."   →  ~/.seashell/inbox.jsonl  (global fallback)

$ cd ~/Github/refactoring-project/sub/dir
$ seashell-msg "..."   →  ~/Github/refactoring-project/.seashell-inbox/inbox.jsonl  (walks up)

$ seashell-msg --global "..." →  ~/.seashell/inbox.jsonl  (forced global)
```

Claude's `read_user_inbox` tool aggregates across the global inbox AND every registered project, with each message labeled by project. No naming, no manual selection — your `cwd` IS your routing.

### The daemon (truly autonomous)

By default, Claude only responds when you're in an active Claude Desktop chat. The optional daemon in [`examples/seashell-daemon/`](examples/seashell-daemon/) makes Seashell **truly real-time**: it watches your inboxes, spawns `claude -p` (Claude Code CLI) when notes arrive, and answers without you needing to be in a chat.

```bash
cd examples/seashell-daemon
./install.sh
```

Uses your **Claude.ai subscription** via `claude -p` — no API key, no per-token billing. See [`examples/seashell-daemon/README.md`](examples/seashell-daemon/README.md).

For the full design — storage layout, routing rules, daemon architecture, troubleshooting — see [`docs/INBOX.md`](docs/INBOX.md).

## Features

### Inbox tools (v1.0+)

- **`read_user_inbox`** — drain unread notes across the global inbox and every registered project; archives them
- **`inbox_count`** — cheap peek with per-project breakdown
- **`inbox_history`** — browse archived messages, filterable by project or text
- **`reply_to_user`** — post a reply to unblock a `seashell-ask`

Paired shell commands: `seashell-msg`, `seashell-ask`, `seashell-init`.

### Direct Wave config tools (no helper needed)

Read or modify `~/.config/waveterm/*.json` directly. Wave watches its config files and reloads on change.

- **`wave_get_settings`** / **`wave_set_setting`** — read and write `settings.json`
- **`wave_get_widgets`** / **`wave_create_widget`** / **`wave_update_widget`** / **`wave_delete_widget`** — manage the widget bar
- **`wave_get_ai_presets`** / **`wave_set_ai_preset`** — manage AI model presets
- **`wave_set_theme`** — change the terminal theme
- **`wave_set_appearance`** — font, transparency, cursor, gap size
- **`wave_get_backgrounds`** — list tab backgrounds

### Helper-block tools (require an in-Wave helper)

The bundled `helper/seashell-helper` runs inside Wave Terminal as a small TCP-RPC proxy with `WAVETERM_JWT` access, exercising the full `wsh` RPC surface.

- **`wave_list_workspaces`** / **`wave_list_blocks`** — query Wave's object model
- **`wave_create_block`** / **`wave_delete_block`** — programmatically create/remove blocks
- **`wave_get_scrollback`** — pull last command's output (or full block scrollback)
- **`wave_get_block_meta`** / **`wave_set_block_meta`** — read/update block metadata
- **`wave_run_in_block`** — execute a command in a fresh Wave block
- **`wave_view_file`** / **`wave_edit_file`** — open files in preview/edit blocks

### Secrets and workspace tools

- **`wave_secret_list/set/get/delete`** — manage Wave's keychain-backed secrets (Tier C)
- **`wave_set_background`** — set tab background
- **`wave_create_fish_widget`** — convenience wrapper for fish-configured widgets
- **`wave_bootstrap_workspace`** — apply a complete project workspace template

### Command execution

- **`execute_command`** — run a shell command, capture output. `show_in_wave=true` makes it visible in a Wave block.
- **`execute_with_auto_retrieve`** — runs and intelligently waits for output
- **`execute_with_streaming`** — streams output in real time
- **`execute_pipeline`** — multi-step pipelines with conditional progression
- **`get_command_output`** / **`list_recent_commands`** — query the local SQLite history

### Templates, profiles, environment

- **`save_template`** / **`run_template`** / **`list_templates`** — save command sequences as named templates
- **`save_workspace_profile`** / **`load_workspace_profile`** — capture per-project shell environments
- **`get_environment_context`** — auto-detect the current project's runtime, git state, package files
- **`capture_environment`** / **`diff_environment`** — snapshot env vars and PATH

### Permission tiers

Every tool is classified by risk tier:

- **Tier A — safe**: read-only and inbox operations — log and proceed
- **Tier B — confirm**: config writes — require a one-time confirmation per call
- **Tier C — approve**: secrets and destructive operations — require explicit approval with a reason

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full tier table.

## Customize via AI

The bundled [`examples/wave-config/`](examples/wave-config/) is **one** opinionated way to set up Wave + fish + Ollama. For a setup that fits *your* preferences, see [`prompts/`](prompts/) — copy-paste-ready prompts you feed into Claude (or any AI) to have it design the configuration around how you actually work.

| Prompt | What it gives you |
|---|---|
| [`install-from-scratch.md`](prompts/install-from-scratch.md) | End-to-end setup walkthrough on a fresh Mac |
| [`configure-wave-ui.md`](prompts/configure-wave-ui.md) | Fonts, theme, cursor, transparency tailored to your screen |
| [`configure-shell-stack.md`](prompts/configure-shell-stack.md) | fish vs zsh, Ollama model size, plugin selection |
| [`configure-widgets.md`](prompts/configure-widgets.md) | A widget bar designed around what you actually check daily |
| [`configure-workflow.md`](prompts/configure-workflow.md) | Big-picture: describe your work, get a complete config plan |

## Examples

| Path | What's inside |
|---|---|
| [`examples/wave-config/`](examples/wave-config/) | Opinionated fish + fastfetch + theme-sync starter, with installer |
| [`examples/wave-config/bin/`](examples/wave-config/bin/) | The `seashell-msg`, `seashell-ask`, `seashell-init` commands |
| [`examples/seashell-daemon/`](examples/seashell-daemon/) | Autonomous inbox responder using Claude Code (`claude -p`) |
| [`examples/test_client.py`](examples/test_client.py) | Reference Python client for the command-receiver TCP port |

## Architecture & docs

- **[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)** — System overview, layers, MCP tool surface, Wave object model
- **[`docs/WAVE_INTEGRATION.md`](docs/WAVE_INTEGRATION.md)** — How Seashell talks to Wave: `wsh`, `WAVETERM_JWT`, RPC mechanism, config schemas
- **[`docs/HELPER_PROTOCOL.md`](docs/HELPER_PROTOCOL.md)** — Wire protocol between the external Seashell server and the in-Wave helper
- **[`docs/INBOX.md`](docs/INBOX.md)** — Storage layout, routing rules, daemon architecture, troubleshooting

## Project layout

```
seashell/
├── README.md                       ← you are here
├── LICENSE                         ← MIT
├── Package.swift                   ← Swift package manifest
├── build.sh / clean.sh             ← build scripts
├── setup.sh                        ← post-clone bootstrap
│
├── Sources/
│   ├── Seashell/                   ← MCP server, tool handlers, Wave adapter
│   │   └── InboxHandlers.swift     ← inbox tools (read/count/history/reply)
│   └── ConfigManager/              ← standalone config-management binary
├── Tests/SeashellTests/            ← unit tests
│
├── helper/seashell-helper          ← in-Wave Python helper (TCP proxy to wsh)
├── config/                         ← Claude Desktop config template
├── docs/                           ← architecture + integration + INBOX docs
├── prompts/                        ← AI-assisted configuration prompts
│
└── examples/
    ├── wave-config/
    │   ├── bin/                    ← seashell-msg, seashell-ask, seashell-init
    │   ├── fish/, fastfetch/       ← starter fish stack
    │   ├── wave/                   ← widgets/settings templates
    │   ├── theme-sync/             ← auto light/dark theme switcher
    │   └── install.sh              ← installs the above into your $HOME
    └── seashell-daemon/            ← autonomous inbox responder via claude -p
```

## Acknowledgments

- **[Wave Terminal](https://github.com/wavetermdev/waveterm)** — the terminal Seashell is built around. Open-source, block-based, deeply scriptable.
- **[Anthropic](https://www.anthropic.com/)** — for the [Model Context Protocol](https://modelcontextprotocol.io), Claude Desktop, and Claude Code.
- **[Ollama](https://ollama.com/)** + the **Qwen** team — for the local LLM that powers the optional natural-language fish layer.
- **[fish shell](https://fishshell.com/)**, **[atuin](https://atuin.sh/)**, **[starship](https://starship.rs/)**, **[zoxide](https://github.com/ajeetdsouza/zoxide)**, **[fastfetch](https://github.com/fastfetch-cli/fastfetch)** — small tools that make the example config worth running.

## License

MIT — see [LICENSE](LICENSE).

Built with 🐚 by Pineapple 🍍
