# Seashell Daemon — autonomous inbox responder

The daemon makes Seashell **truly real-time**. While the basic `seashell-msg` / `read_user_inbox` flow waits for you to be in an active Claude Desktop chat, the daemon watches your inboxes continuously and answers on its own using Claude Code (`claude -p`).

## What it does

```
┌─────────────────────┐     ~/.seashell/         ┌─────────────────────┐
│  seashell-msg /     │  inbox.jsonl files       │  seashell-daemon    │
│  seashell-ask       │  ─── append ──>          │  (LaunchAgent)      │
│  (any Wave block)   │                          │                     │
└─────────────────────┘                          │  Polls every 5s     │
                                                 │  When unread > 0:   │
                                                 │  cd <project>       │
                                                 │  claude -p "..."    │
                                                 │     ▼               │
                                                 │  Claude calls       │
                                                 │  read_user_inbox    │
                                                 │  + reply_to_user    │
                                                 └─────────────────────┘
```

When you `seashell-ask "what's the update?"` from any terminal, the daemon notices within 5 seconds, spawns `claude -p` from the right project directory, Claude reads the message via the MCP tools, posts a reply, your terminal unblocks. Real-time async with no Claude Desktop in the loop.

## Why no API key

`claude -p` is the Claude Code CLI in non-interactive mode. It authenticates via your **Claude.ai Pro/Max subscription** (the same login Claude Desktop uses). No `sk-ant-...` API key. No per-token billing. You're using subscription quota.

## Install

### Prerequisites

1. **Claude Code CLI** — install per [Anthropic's docs](https://docs.claude.com/claude-code), then:
   ```bash
   claude auth login    # OAuth into your Claude.ai account
   ```

2. **Seashell** — the main Seashell server installed and built (`~/Github/seashell/.build/release/seashell` exists).

3. **Register Seashell with Claude Code** so the daemon's `claude -p` invocations can call its MCP tools:
   ```bash
   claude mcp add seashell ~/Github/seashell/.build/release/seashell
   ```

### Install the daemon

```bash
cd ~/Github/seashell/examples/seashell-daemon
./install.sh
```

The installer:
1. Verifies `claude` CLI is present and the seashell MCP server is registered
2. Copies `seashell-daemon` to `~/.local/bin/`
3. Generates `~/Library/LaunchAgents/dev.seashell.daemon.plist` with your real `$HOME`
4. Loads the LaunchAgent — it starts immediately and on every login

## Try it

After install, from any directory you've `seashell-init`'d:

```bash
cd ~/Github/your-project
seashell-init                       # if you haven't already
seashell-ask "what's the update?"   # blocks waiting for reply
```

Within ~5–10 seconds, the daemon picks up the question, runs Claude in your project directory, Claude responds via `reply_to_user`, your terminal unblocks with the answer.

## Operations

| Need | Command |
|---|---|
| Status | `launchctl list \| grep dev.seashell.daemon` |
| Tail logs | `tail -f /tmp/seashell-daemon.log` |
| Stop | `launchctl unload ~/Library/LaunchAgents/dev.seashell.daemon.plist` |
| Restart | `./install.sh` (idempotent) |
| Manual single pass | `~/.local/bin/seashell-daemon once` |
| List watched inboxes | `~/.local/bin/seashell-daemon list` |

## Tuning

```bash
# Slower polling (less responsive, fewer claude invocations):
launchctl setenv SEASHELL_DAEMON_POLL 30

# Longer max claude run-time (for complex prompts):
launchctl setenv SEASHELL_DAEMON_CLAUDE_TIMEOUT 300

# Custom log location:
launchctl setenv SEASHELL_DAEMON_LOG ~/seashell-daemon.log
```

After changing env vars, reload: `launchctl unload ... && launchctl load -w ...`.

## Caveats

- **Claude.ai subscription rate limits apply.** The daemon batches per-project; one `claude -p` invocation per project per polling cycle. For typical use (a handful of messages per hour) this is well within limits. For high-volume traffic, consider increasing `SEASHELL_DAEMON_POLL`.
- **The daemon's Claude session is fresh each time** — no conversation history across messages. Each inbox handling is independent.
- **`claude -p` can take 5-30 seconds.** First-time invocations are slower due to model warmup. If `seashell-ask` times out before the daemon responds, increase the `--timeout` argument.
- **Per-project CLAUDE.md** is loaded automatically by `claude -p` because we `cd` into the project first. Keep that file's inbox hint up to date.

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/dev.seashell.daemon.plist
rm ~/Library/LaunchAgents/dev.seashell.daemon.plist
rm ~/.local/bin/seashell-daemon
```

Optionally also: `claude mcp remove seashell`.
