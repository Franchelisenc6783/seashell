# Seashell Inbox — design and operations

The inbox is Seashell's bidirectional async layer: it lets you leave Claude notes from any terminal block (or pipe command output to Claude for analysis), and lets Claude reply back to commands that block waiting for an answer. With the optional daemon, Claude responds autonomously even when you're not in an active chat.

This document covers the storage layout, routing rules, the four MCP tools, the three shell commands, the daemon architecture, and troubleshooting.

---

## Mental model

```
┌──────────────────────┐                        ┌──────────────────────┐
│  Wave Terminal       │   ~/.seashell/         │  Claude              │
│  (any block)         │   <project>/           │  (Desktop or Code)   │
│                      │   .seashell-inbox/     │                      │
│  $ seashell-msg ...  │   ┌──────────────┐     │                      │
│  $ seashell-ask ...  │ → │ inbox.jsonl  │ →   │  read_user_inbox     │
│                      │   │              │     │  inbox_count         │
│                      │   ├──────────────┤ ←   │  reply_to_user       │
│                      │   │ replies.jsonl│     │                      │
│  ⏳ waiting...        │   ├──────────────┤     │                      │
│  ✓ <claude reply>    │ ← │  archive.    │     │                      │
│                      │   │   jsonl      │     │                      │
└──────────────────────┘   └──────────────┘     └──────────────────────┘
```

**Three flows:**

1. **Fire-and-forget** — `seashell-msg "note"` writes to inbox; Claude picks it up next chat turn via `read_user_inbox`. No reply expected.
2. **Blocking ask** — `seashell-ask "?"` writes a record with a `reply_token` and polls `replies.jsonl`. Claude calls `reply_to_user(message_id, text)` to unblock.
3. **Autonomous (with daemon)** — `seashell-daemon` watches inboxes, spawns `claude -p` from each project's directory when unread > 0, Claude handles the inbox via MCP tools.

## Storage layout

### Global inbox (no project context)

```
~/.seashell/
├── inbox.jsonl                  unread queue (append-only)
├── inbox.processing.jsonl       transient, used during atomic drain
├── inbox.archive.jsonl          read messages (audit trail)
├── replies.jsonl                Claude's replies to seashell-ask
└── projects.jsonl               registry of known project paths
```

### Per-project inbox

```
<project_path>/.seashell-inbox/
├── inbox.jsonl
├── inbox.processing.jsonl
├── inbox.archive.jsonl
├── replies.jsonl
├── README.md                    explainer
└── .gitignore                   excludes the .jsonl files
```

`seashell-init` creates this directory and registers the project in `~/.seashell/projects.jsonl`.

## Record formats

### `inbox.jsonl` — InboxRecord

```json
{
  "id": "73c9c0f4-4c60-4229-9c7a-3ed104de87eb",
  "ts": "2026-04-25T07:05:38Z",
  "cwd": "/Users/me/Github/refactoring-project",
  "hostname": "my-mac.local",
  "text": "compare the test output to what we just discussed",
  "read": false,
  "attachments": [
    {"type": "file", "path": "/tmp/build.log"}
  ],
  "reply_token": "49ca3c2a3a5fcf36d0da4dbe088ca3bc"
}
```

`reply_token` is only set when posted by `seashell-ask`. Its presence tells Claude "the user is blocking on this — answer via `reply_to_user`."

### `replies.jsonl` — ReplyRecord

```json
{
  "message_id": "73c9c0f4-4c60-4229-9c7a-3ed104de87eb",
  "ts": "2026-04-25T07:06:01Z",
  "text": "Tests are passing. The refactor's regression suite is green.",
  "hostname": "my-mac.local"
}
```

`seashell-ask` polls this file every 0.5s for a matching `message_id`.

### `projects.jsonl` — ProjectRegistryEntry

```json
{"path": "/Users/me/Github/refactoring-project", "name": "refactoring-project", "added_at": "2026-04-25T07:00:00Z"}
```

Append-only. `seashell-init` checks for existing entries before adding.

## Routing rules

`seashell-msg` and `seashell-ask` walk up from `$PWD` to find the nearest `.seashell-inbox/` directory:

```
$ cd ~/Github/refactoring-project/sub/dir
$ seashell-msg "..."

# Walk:
#   /Users/me/Github/refactoring-project/sub/dir/.seashell-inbox/      ← no
#   /Users/me/Github/refactoring-project/sub/.seashell-inbox/          ← no
#   /Users/me/Github/refactoring-project/.seashell-inbox/              ← YES, write here
```

If no marker is found, falls back to `~/.seashell/inbox.jsonl` (global).

Pass `--global` to force global routing even when inside a project. Useful for general questions that aren't project-scoped.

## The MCP tools

All four tools are **Tier A (safe)** — read-only or append-only operations.

### `read_user_inbox`

Drains unread messages across the global inbox AND every registered project. For each inbox:

1. Atomic rename: `inbox.jsonl` → `inbox.processing.jsonl` (concurrent writes by `seashell-msg` immediately start a fresh `inbox.jsonl`, no loss).
2. Parse processing.jsonl line by line.
3. Mark each record `read=true` and append to `archive.jsonl`.
4. Delete `processing.jsonl`.

Returns rendered text grouped by project, with `reply_token` annotations where present.

### `inbox_count`

Cheap peek that doesn't drain. Returns total unread + age of oldest + per-project breakdown. Suitable for calling on every chat turn (e.g., as part of CLAUDE.md guidance for ambiguous user messages like "?", "continue", "check inbox").

### `inbox_history`

Browses archived messages with optional `limit` (1-100, default 20), `search` (substring filter), and `project` (label filter). Sorted most-recent-first.

### `reply_to_user`

Appends a `ReplyRecord` to the appropriate `replies.jsonl`. Routing:

1. If `project_path` argument provided → use that project's `.seashell-inbox/replies.jsonl`.
2. Otherwise: search archives across all known inboxes for the `message_id`, use whichever owns it.
3. Final fallback: global `~/.seashell/replies.jsonl`.

The blocking `seashell-ask` polls its scoped `replies.jsonl` for the matching `message_id` and prints the reply when found.

## The shell commands

### `seashell-msg`

Plain notes (no reply expected):

```bash
seashell-msg "context note"
command | seashell-msg "explain this"
seashell-msg --file /path/to/log "investigate"
seashell-msg --global "skip cwd routing"
```

### `seashell-ask`

Blocking — posts and polls for a matching reply:

```bash
seashell-ask "what's the status?"
seashell-ask --timeout 60 "wait up to 60s"
seashell-ask --no-wait "post and exit"        # prints message_id, doesn't block
command | seashell-ask "explain this output"
```

If `--timeout` (default 600s = 10 min) elapses with no reply, exits with code 124.

### `seashell-init`

Idempotent project setup:

```bash
seashell-init                  # uses $PWD
seashell-init /path/to/project # explicit
```

Creates `.seashell-inbox/`, adds to registry, writes (or extends) `CLAUDE.md` with an inbox hint.

## The daemon

See [`examples/seashell-daemon/README.md`](../examples/seashell-daemon/README.md) for install. Architecture:

```
seashell-daemon (LaunchAgent, runs continuously)
    │
    ├─ every 5s: list inboxes (global + every registered project)
    │
    └─ if any unread:
       └─ for each inbox with unread:
          └─ cd <project_cwd>
             └─ claude -p "You have N unread inbox messages. Read and respond..."
                └─ Claude (using its registered MCP servers including seashell)
                   ├─ calls read_user_inbox  → drains messages
                   ├─ for each with reply_token:
                   │  └─ calls reply_to_user(message_id, text)
                   └─ exits
       └─ next poll
```

Key properties:

- **Per-project Claude sessions.** Each invocation `cd`s to the project's directory, so Claude inherits the project's `CLAUDE.md` and any project-scoped MCP servers.
- **No conversation history across messages.** Each `claude -p` invocation is fresh. If you need continuity, include context in your `seashell-msg` text.
- **Subscription auth.** Uses your Claude.ai login via the `claude` CLI. No API key.
- **Rate limit awareness.** One Claude invocation per project per polling cycle. Tune `SEASHELL_DAEMON_POLL` for high-volume traffic.

## Concurrency and safety

- **Append from `seashell-msg` is safe.** Single `echo >>` writes are atomic for sub-page-size strings on Unix filesystems. JSONL records are typically far under that limit.
- **Drain via atomic rename.** `read_user_inbox` does `mv inbox.jsonl inbox.processing.jsonl` first. Any concurrent `seashell-msg` after that point creates a fresh `inbox.jsonl` — no loss.
- **Crash recovery.** If `read_user_inbox` is killed mid-drain, `inbox.processing.jsonl` is left behind. The next `read_user_inbox` call detects it and processes it before draining the new inbox.
- **`reply_to_user`** is append-only — multiple Claude sessions writing replies don't conflict.

## Permissions and privacy

- All inbox tools are **Tier A (safe)**. They never execute arbitrary code on your behalf.
- Inbox content is **stored locally on your machine.** No network traffic from `seashell-msg` / `seashell-ask`.
- The daemon's `claude -p` invocations DO send your inbox content to Anthropic's servers (that's how Claude responds). This matches what happens any time you talk to Claude.
- The example installer adds `.seashell-inbox/.gitignore` to keep JSONL contents out of version control.

## Troubleshooting

### "📭 Inbox empty" but I just wrote a note

- The `seashell-msg` you ran might have routed to a different inbox than the one Claude is checking. Run `seashell-msg --global "..."` to force global, or check `~/.seashell/projects.jsonl` to see which projects are registered.

### `seashell-ask` times out

- The default timeout is 600s. If you don't have an active Claude conversation OR the daemon isn't running, no one is reading the inbox. Either:
  - Open Claude Desktop and type `?` to wake Claude up.
  - Install the daemon for hands-off operation.

### Daemon installed but messages aren't getting answered

```bash
launchctl list | grep dev.seashell.daemon    # is it running?
tail -f /tmp/seashell-daemon.log              # watch live
~/.local/bin/seashell-daemon list             # see what it's watching
~/.local/bin/seashell-daemon once             # manual single-pass test
```

If the daemon is running but `claude -p` is failing, check:

```bash
claude --version                              # is the CLI working?
claude auth status                            # are you authenticated?
claude mcp list                               # is seashell registered?
```

### Reply doesn't unblock my `seashell-ask`

The `seashell-ask` polls the **same project's** `replies.jsonl`. If `reply_to_user` was called with no `project_path` and the message_id couldn't be auto-detected, the reply may have landed in the global file instead. Check both:

```bash
tail ~/.seashell/replies.jsonl
tail <project>/.seashell-inbox/replies.jsonl
```

### Multiple projects registered with the same path

The dedupe check prevents this in `seashell-init`, but if you ran an older version, dedupe manually:

```bash
python3 -c "
import json
seen = set(); out = []
for line in open('$HOME/.seashell/projects.jsonl'):
    line = line.strip()
    if not line: continue
    e = json.loads(line)
    if e.get('path') in seen: continue
    seen.add(e.get('path'))
    out.append(line)
open('$HOME/.seashell/projects.jsonl','w').write('\n'.join(out)+'\n')
"
```

## Future work (post-v1.0)

- **Cross-machine sync.** Symlinking `~/.seashell/` into iCloud Drive or a synced repo would let multiple machines share inbox state. Untested but should work for `inbox.jsonl` + `archive.jsonl`. Not recommended for `replies.jsonl` (race-prone with multiple Claudes).
- **Native MCP sampling.** If/when Claude Desktop adds robust `notifications/sampling/createMessage` support, the daemon could become unnecessary.
- **Direct Anthropic API mode.** A `seashell-daemon-api` variant for users who prefer per-token billing over Claude.ai subscription auth.
