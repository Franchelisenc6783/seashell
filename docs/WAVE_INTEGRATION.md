# Wave Terminal integration strategy

## How wsh actually works (from source code analysis)

This section is derived from reading the Wave Terminal source code at `https://github.com/wavetermdev/waveterm`, specifically the `cmd/wsh/` directory and `pkg/wshutil/` package.

### Authentication mechanism

`wsh` connects to Wave via **Unix domain socket + JWT authentication**:

1. Wave Terminal sets `WAVETERM_JWT` environment variable in every terminal block it spawns
2. `wsh` reads this JWT, extracts a socket name from it
3. Connects to Wave's domain socket via `wshutil.SetupDomainSocketRpcClient()`
4. Authenticates using `wshclient.AuthenticateCommand()`
5. All subsequent commands use this authenticated RPC connection

**Critical constraint**: `WAVETERM_JWT` is only available inside Wave-managed terminal blocks. External processes (like our MCP server running via Claude Desktop) do not have this token.

### Environment variables set by Wave

| Variable | Purpose |
|----------|---------|
| `WAVETERM_JWT` | Authentication token for domain socket RPC |
| `WAVETERM_BLOCKID` | Current block's unique ID |
| `WAVETERM_TABID` | Current tab's unique ID |

### wsh command inventory (from source)

Every `wshcmd-*.go` file in `cmd/wsh/cmd/` maps to a wsh subcommand:

| Command | File | What it does | Requires JWT |
|---------|------|-------------|-------------|
| `wsh ai` | wshcmd-ai.go | Append files/text to Wave AI sidebar | Yes |
| `wsh badge` | wshcmd-badge.go | Set tab badge | Yes |
| `wsh blocks list` | wshcmd-blocks.go | List blocks with filtering by workspace/tab/view | Yes |
| `wsh conn` | wshcmd-conn.go | Manage SSH connections | Yes |
| `wsh createblock` | wshcmd-createblock.go | Create a new block (hidden command) | Yes |
| `wsh debug` | wshcmd-debug.go | Debug utilities | Yes |
| `wsh deleteblock` | wshcmd-deleteblock.go | Delete a block | Yes |
| `wsh edit` | wshcmd-editor.go | Open file for editing | Yes |
| `wsh editconfig` | wshcmd-editconfig.go | Open Wave config file for editing | Yes |
| `wsh file` | wshcmd-file.go | File operations (copy, sync between hosts) | Yes |
| `wsh focusblock` | wshcmd-focusblock.go | Focus a specific block | Yes |
| `wsh getmeta` | wshcmd-getmeta.go | Get block/entity metadata | Yes |
| `wsh getvar` | wshcmd-getvar.go | Get a variable value | Yes |
| `wsh launch` | wshcmd-launch.go | Launch applications | Yes |
| `wsh notify` | wshcmd-notify.go | Send notifications | Yes |
| `wsh readfile` | wshcmd-readfile.go | Read a file | Yes |
| `wsh run` | wshcmd-run.go | Run command in a new block | Yes |
| `wsh secret` | wshcmd-secret.go | Manage secrets (get/set/list/delete/ui) | Yes |
| `wsh setbg` | wshcmd-setbg.go | Set tab background image/colour | Yes |
| `wsh setconfig` | wshcmd-setconfig.go | Set config key-value pairs | Yes |
| `wsh setmeta` | wshcmd-setmeta.go | Set block/entity metadata | Yes |
| `wsh setvar` | wshcmd-setvar.go | Set a variable | Yes |
| `wsh ssh` | wshcmd-ssh.go | SSH connection management | Yes |
| `wsh tabindicator` | wshcmd-tabindicator.go | Set tab indicator | Yes |
| `wsh term` | wshcmd-term.go | Terminal operations | Yes |
| `wsh termscrollback` | wshcmd-termscrollback.go | Get terminal scrollback content | Yes |
| `wsh token` | wshcmd-token.go | Exchange token for shell init script | Yes |
| `wsh version` | wshcmd-version.go | Show version | No |
| `wsh view` / `preview` / `open` | wshcmd-view.go | Preview/edit file or open URL | Yes |
| `wsh wavepath` | wshcmd-wavepath.go | Get Wave directory paths | Yes |
| `wsh web` | wshcmd-web.go | Web-related operations | Yes |
| `wsh workspace list` | wshcmd-workspace.go | List workspaces | Yes |

### Key wsh RPC calls used internally

These are the actual Go RPC client calls that wsh commands invoke:

```
wshclient.WorkspaceListCommand()         → list workspaces
wshclient.BlocksListCommand()            → list blocks
wshclient.CreateBlockCommand()           → create block
wshclient.DeleteBlockCommand()           → delete block
wshclient.SetMetaCommand()               → set entity metadata
wshclient.GetMetaCommand()               → get entity metadata
wshclient.SetConfigCommand()             → update settings
wshclient.GetSecretsCommand()            → retrieve secrets
wshclient.GetSecretsNamesCommand()       → list secret names
wshclient.SetSecretsCommand()            → set/delete secrets
wshclient.TermGetScrollbackLinesCommand()→ get terminal scrollback
wshclient.ResolveIdsCommand()            → resolve block references
wshclient.WaveAIAddContextCommand()      → add context to AI chat
```

## Integration strategy: two-tier approach

### Tier 1: direct config file I/O (no JWT needed)

Wave stores its configuration in JSON files at `~/.waveterm/`. These files can be read and written by any process with filesystem access. No JWT or domain socket needed.

**What this enables**:
- Read all settings (`settings.json`)
- Read and write widgets (`widgets.json`)
- Read and write AI presets (`aipresets.json`)
- Read and write backgrounds (`backgrounds.json`)
- Read connection configs (`connections.json`)

**How Wave reacts to config changes**:
- Wave watches its config files for changes (file system events)
- When a config file changes on disk, Wave reloads it automatically
- This means our MCP server can write to `widgets.json` and Wave picks up the new widget immediately
- Same for settings, AI presets, and backgrounds

**This is the primary integration surface — no in-Wave helper required.**

### Tier 2: helper block proxy (uses JWT via in-Wave helper)

For operations that require wsh RPC (block creation, scrollback, secrets), we deploy a lightweight helper process that runs inside Wave.

**Architecture**:

```
MCP Server (external) ──TCP──→ Helper Block (inside Wave) ──domain socket──→ Wave RPC
```

The helper is a small Go or shell script that:
1. Runs as a persistent Wave widget (defined in widgets.json)
2. Has access to WAVETERM_JWT, WAVETERM_BLOCKID, WAVETERM_TABID
3. Listens on localhost TCP port (e.g., 9877)
4. Accepts simple JSON-RPC requests from our MCP server
5. Translates them to wsh RPC calls
6. Returns results

**What this enables** (beyond Tier 1):
- List workspaces and their metadata
- List blocks with view type, tab, workspace filtering
- Create new blocks (terminal, preview, web, AI)
- Delete blocks
- Get terminal scrollback (including last command output)
- Set block metadata (theme, font, shell per-block)
- Focus specific blocks
- Manage secrets (get, set, list, delete)
- Open files for editing or preview
- Run commands in new Wave blocks
- Send context to Wave AI

## Wave config file reference

### `~/.waveterm/settings.json`

Global settings. Key namespaces:

```json
{
  "ai:preset": "string",
  "ai:apitype": "string",
  "ai:baseurl": "string",
  "ai:model": "string",
  "ai:maxtokens": 4096,
  "term:fontsize": 14,
  "term:fontfamily": "JetBrains Mono",
  "term:theme": "default-dark",
  "term:localshellpath": "/opt/homebrew/bin/fish",
  "term:localshellopts": ["--login"],
  "term:scrollback": 10000,
  "term:copyonselect": true,
  "window:transparent": false,
  "window:bgcolor": "#1e1e2e",
  "window:opacity": 1.0,
  "window:tilegapsize": 3,
  "app:globalhotkey": "Ctrl+Space",
  "app:confirmquit": true,
  "tab:preset": "string",
  "editor:minimapenabled": false,
  "editor:wordwrap": true,
  "web:defaulturl": "https://google.com",
  "telemetry:enabled": false
}
```

### `~/.waveterm/widgets.json`

Custom widget definitions. Each key is a widget ID:

```json
{
  "my-dev-server": {
    "icon": "server",
    "color": "#1172BA",
    "label": "Dev Server",
    "description": "Start development server",
    "magnified": false,
    "workspaces": ["workspace-id-1"],
    "blockdef": {
      "meta": {
        "view": "term",
        "controller": "cmd",
        "cmd": "npm run dev",
        "cmd:cwd": "/path/to/project",
        "cmd:runonstart": true,
        "cmd:closeonexit": false,
        "cmd:env": {
          "NODE_ENV": "development"
        },
        "term:fontsize": 13,
        "term:theme": "dracula"
      },
      "files": {}
    }
  }
}
```

**Widget blockdef meta keys** (from schema analysis):

| Key | Type | Purpose |
|-----|------|---------|
| `view` | `"term" \| "preview" \| "web" \| "sysinfo" \| "launcher"` | Block type |
| `controller` | `"shell" \| "cmd"` | Shell = interactive, cmd = run command |
| `cmd` | string | Command to execute |
| `cmd:cwd` | string | Working directory |
| `cmd:env` | object | Environment variables |
| `cmd:runonstart` | boolean | Auto-run when block opens |
| `cmd:runonce` | boolean | Run only once |
| `cmd:persistent` | boolean | Keep block alive |
| `cmd:closeonexit` | boolean | Close on successful exit |
| `cmd:closeonexitforce` | boolean | Close on any exit |
| `cmd:closeonexitdelay` | number | Delay before closing (ms) |
| `cmd:clearonstart` | boolean | Clear output on restart |
| `cmd:shell` | boolean | Use shell to interpret command |
| `cmd:interactive` | boolean | Interactive mode |
| `cmd:login` | boolean | Login shell |
| `cmd:args` | string[] | Command arguments |
| `cmd:nowsh` | boolean | Disable wsh in this block |
| `cmd:initscript` | string | Init script (generic) |
| `cmd:initscript.fish` | string | Fish-specific init script |
| `cmd:initscript.zsh` | string | Zsh-specific init script |
| `cmd:initscript.bash` | string | Bash-specific init script |
| `term:fontsize` | integer | Terminal font size |
| `term:fontfamily` | string | Terminal font |
| `term:theme` | string | Terminal theme |
| `term:localshellpath` | string | Shell binary path |
| `term:localshellopts` | string[] | Shell launch options |
| `term:scrollback` | integer | Scrollback lines |
| `term:transparency` | number | Terminal transparency |
| `term:durable` | boolean | Durable session |
| `file` | string | File path (for preview/edit) |
| `url` | string | URL (for web blocks) |

**Widget display properties**:

| Key | Type | Purpose |
|-----|------|---------|
| `icon` | string | Icon name |
| `color` | string | Colour |
| `label` | string | Display label |
| `description` | string | Tooltip description |
| `display:order` | number | Sort order in widget bar |
| `display:hidden` | boolean | Hide from widget bar |
| `magnified` | boolean | Open in magnified mode |
| `workspaces` | string[] | Limit to specific workspaces |

### `~/.waveterm/aipresets.json`

AI model presets. Each key is a preset name:

```json
{
  "ollama-llama": {
    "display:name": "Ollama Llama 3",
    "display:order": 1,
    "ai:apitype": "openai",
    "ai:baseurl": "http://localhost:11434/v1",
    "ai:model": "llama3",
    "ai:maxtokens": 4096,
    "ai:name": "Local Llama"
  },
  "claude-sonnet": {
    "display:name": "Claude Sonnet",
    "display:order": 2,
    "ai:apitype": "anthropic",
    "ai:model": "claude-sonnet-4-20250514",
    "ai:maxtokens": 8192,
    "ai:name": "Claude Sonnet"
  }
}
```

### `~/.waveterm/backgrounds.json`

Tab background definitions. Structure follows the backgrounds schema.

## Fish shell integration

Wave supports fish shell natively via widget configuration:

```json
{
  "fish-terminal": {
    "icon": "fish",
    "label": "Fish Shell",
    "blockdef": {
      "meta": {
        "view": "term",
        "controller": "shell",
        "term:localshellpath": "/opt/homebrew/bin/fish",
        "term:localshellopts": ["--login"],
        "cmd:initscript.fish": "set -gx PROJECT_ROOT /path/to/project\ncd $PROJECT_ROOT"
      }
    }
  }
}
```

Key fields for fish automation:
- `term:localshellpath` → set to fish binary
- `term:localshellopts` → `["--login"]` for login shell
- `cmd:initscript.fish` → fish-specific initialisation script

## Theme integration

Terminal themes are set via the `term:theme` setting key:

```json
{
  "term:theme": "dracula"
}
```

This can be set globally in `settings.json` or per-block in widget definitions.

Available built-in themes can be discovered by reading Wave's theme directory (location varies by installation). Custom themes can be defined in Wave's theme system.

Additional appearance controls via settings:
- `term:fontsize` / `term:fontfamily` – terminal typography
- `window:bgcolor` – window background colour
- `window:transparent` / `window:opacity` – transparency
- `window:blur` – blur effect
- `window:tilegapsize` – gap between blocks

Per-tab appearance via `wsh setbg`:
- Background images (jpg, png, gif, webp, svg)
- Solid colours (hex or CSS colour names)
- Opacity, tiling, centering options
- Border colours for block frames

## Secrets integration

Wave secrets use native system keychain backends:

- **macOS**: Keychain
- **Linux**: Secret Service API (or basic_text fallback)

Secret operations via wsh:
- `wsh secret list` → list names only
- `wsh secret get NAME` → retrieve value
- `wsh secret set NAME=VALUE` → store value
- `wsh secret delete NAME` → remove
- `wsh secret ui` → open secrets management UI

Secret name validation: must match `^[A-Za-z][A-Za-z0-9_]*$`

**Security note**: If the Linux backend is `basic_text` or `unknown`, Wave refuses to set secrets. Our MCP server should respect this constraint.

## Wave Terminal detection

To detect if Wave Terminal is installed on macOS:

1. Check for bundle ID via `NSWorkspace` (need to determine Wave's exact bundle ID)
2. Check for `~/.waveterm/` config directory existence
3. Check for `wsh` binary in PATH
4. Check for `WAVETERM_JWT` environment variable (only inside Wave)

For Tier 1 detection, checking `~/.waveterm/` directory existence is sufficient.
