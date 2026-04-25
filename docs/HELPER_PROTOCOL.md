# Wave Helper Block Protocol

## Overview

A lightweight helper process runs **inside** Wave Terminal. Because `WAVETERM_JWT` is only available inside Wave-managed terminal blocks, this helper acts as an authenticated proxy between the external MCP server and Wave's internal RPC system.

```
Claude Desktop
    │ MCP (stdio JSON-RPC)
    ▼
MCP Server (Swift binary, external)
    │ TCP JSON-RPC — localhost:9877
    ▼
Helper Block (shell script inside Wave, has WAVETERM_JWT)
    │ Unix domain socket + JWT
    ▼
Wave Terminal RPC (wsh commands)
```

## Helper block definition

The helper is a Wave widget defined in `widgets.json`. When the user opens it, the block spawns the helper script inside Wave with full `WAVETERM_JWT` access.

```json
{
  "seashell-helper": {
    "icon": "robot",
    "color": "#6C63FF",
    "label": "Seashell Helper",
    "description": "Bridge between Claude MCP server and Wave Terminal RPC",
    "blockdef": {
      "meta": {
        "view": "term",
        "controller": "cmd",
        "cmd": "seashell-helper",
        "cmd:runonstart": true,
        "cmd:persistent": true,
        "cmd:closeonexit": false,
        "cmd:env": {
          "SEASHELL_HELPER_PORT": "9877"
        }
      }
    }
  }
}
```

The MCP server writes this widget definition on startup (if `helperEnabled: true`) and the user opens it once manually.

## Transport

- **Protocol**: newline-delimited JSON over TCP
- **Host**: `127.0.0.1`
- **Port**: configurable, default `9877` (from `config.wave.helperPort`)
- **Encoding**: UTF-8
- **Framing**: each message terminated by `\n`

## Request format

```json
{"id": 1, "method": "wave.listWorkspaces", "params": {}}
{"id": 2, "method": "wave.listBlocks", "params": {"workspace_id": "abc"}}
```

Fields:
- `id` (integer): correlates response to request
- `method` (string): one of the methods below
- `params` (object): method-specific parameters

## Response format

Success:
```json
{"id": 1, "result": [...]}
```

Error:
```json
{"id": 1, "error": {"code": -32001, "message": "wsh: block not found"}}
```

## Methods

### `wave.ping`
Health check. Returns `{"ok": true}`.

### `wave.listWorkspaces`
Returns all Wave workspaces.

**params**: `{}`

**result**: `[{"workspace_id": "...", "name": "...", "icon": "...", "color": "..."}]`

### `wave.listBlocks`
Returns blocks, optionally filtered.

**params**: `{"workspace_id?": "...", "tab_id?": "...", "view?": "term|preview|web|sysinfo"}`

**result**: `[{"block_id": "...", "tab_id": "...", "workspace_id": "...", "view": "...", "meta": {...}}]`

### `wave.createBlock`
Create a new block in a tab.

**params**: `{"tab_id": "...", "meta": {"view": "term", "controller": "cmd", "cmd": "...", ...}}`

**result**: `{"block_id": "...", "oref": "..."}`

### `wave.deleteBlock`
Delete a block.

**params**: `{"block_id": "..."}`

**result**: `{"ok": true}`

### `wave.getScrollback`
Retrieve terminal scrollback from a block.

**params**: `{"block_id": "...", "last_command_only?": false}`

**result**: `{"lines": ["...", ...], "line_count": 42}`

### `wave.getBlockMeta`
Read metadata for a block.

**params**: `{"block_id": "..."}`

**result**: `{"meta": {"view": "...", "cmd": "...", ...}}`

### `wave.setBlockMeta`
Update metadata for a block (hot-reload capable).

**params**: `{"block_id": "...", "meta": {"term:theme": "dracula", ...}}`

**result**: `{"ok": true}`

### `wave.runCommand`
Run a command in a new terminal block.

**params**: `{"tab_id": "...", "command": "...", "cwd?": "...", "env?": {...}, "close_on_exit?": true}`

**result**: `{"block_id": "..."}`

### `wave.viewFile`
Open a file in a preview block.

**params**: `{"tab_id": "...", "file": "..."}`

**result**: `{"block_id": "..."}`

### `wave.editFile`
Open a file for editing in a block.

**params**: `{"tab_id": "...", "file": "..."}`

**result**: `{"block_id": "..."}`

## Error codes

| Code    | Meaning                        |
|---------|--------------------------------|
| -32700  | Parse error (malformed JSON)   |
| -32600  | Invalid request                |
| -32601  | Method not found               |
| -32602  | Invalid params                 |
| -32603  | Internal error                 |
| -32001  | wsh command failed             |
| -32002  | Wave not available (no JWT)    |
| -32003  | Block not found                |
| -32004  | Tab not found                  |

## Helper script behaviour

The helper shell script (`seashell-helper`):

1. Checks for `WAVETERM_JWT` — exits immediately if missing (not running inside Wave)
2. Reads `SEASHELL_HELPER_PORT` (default: 9877)
3. Starts a TCP listener using `socat` or Python (whichever is available)
4. For each incoming JSON request: parses method + params, runs the appropriate `wsh` command, returns the result as JSON
5. Logs to stderr (visible in the Wave block)
6. Runs indefinitely until the block is closed

## Security considerations

- Helper only binds to `127.0.0.1` (loopback only)
- No authentication between MCP server and helper (trusted localhost)
- Secret operations require Tier C approval before being forwarded
- Helper exits immediately if `WAVETERM_JWT` is missing

## MCP server connection lifecycle

1. On startup, `WaveHelperClient` attempts to connect if `config.wave.helperEnabled == true`
2. If connection fails, helper-block tools return a clear error message explaining how to start the helper block
3. Connection is maintained as a persistent TCP stream
4. Heartbeat via `wave.ping` every 30 seconds
5. On disconnect: log warning, retry with exponential backoff (max 60s)
6. Tier-1 tools (direct config file I/O) always work regardless of helper connection state
