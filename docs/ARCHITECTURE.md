# Architecture

## System overview

```
┌─────────────────────────────────────────────────────┐
│                   Claude Desktop                     │
│                                                     │
│  Calls MCP tools via stdio JSON-RPC                 │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│              MCP Server (Swift binary)               │
│                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │
│  │ Tool Router  │  │ Permission   │  │ Structured│ │
│  │ (CallTool    │  │ Guard        │  │ Logger    │ │
│  │  dispatch)   │  │ (Tier A/B/C) │  │           │ │
│  └──────┬───────┘  └──────────────┘  └───────────┘ │
│         │                                           │
│  ┌──────┴───────────────────────────────────────┐   │
│  │              Handler Layer                    │   │
│  │                                              │   │
│  │  ┌─────────────┐  ┌──────────────────────┐   │   │
│  │  │ Config      │  │ Command Execution    │   │   │
│  │  │ Handlers    │  │ Handlers (reused)    │   │   │
│  │  └──────┬──────┘  └──────────┬───────────┘   │   │
│  │         │                    │               │   │
│  │  ┌──────┴──────┐  ┌─────────┴────────────┐   │   │
│  │  │ Wave Config │  │ Wave Helper Client   │   │   │
│  │  │ Adapter     │  │ (TCP → helper block) │   │   │
│  │  └──────┬──────┘  └─────────┬────────────┘   │   │
│  │         │                    │               │   │
│  └─────────┼────────────────────┼───────────────┘   │
│            │                    │                   │
│  ┌─────────┴───────┐  ┌────────┴────────────────┐   │
│  │ SQLite Layer    │  │ Process Executor        │   │
│  │ (DatabaseMgr)   │  │ (subprocess)            │   │
│  └─────────────────┘  └─────────────────────────┘   │
└─────────────────────────────────────────────────────┘
         │                          │
         ▼                          ▼
┌────────────────┐        ┌──────────────────────┐
│ ~/.waveterm/   │        │ Wave Terminal app     │
│                │        │                      │
│ settings.json  │        │ ┌──────────────────┐ │
│ widgets.json   │        │ │ Helper Block     │ │
│ aipresets.json │        │ │ (has WAVETERM_JWT)│ │
│ backgrounds.json│       │ │                  │ │
│ connections.json│       │ │ Listens on TCP   │ │
│                │        │ │ Proxies wsh RPC  │ │
└────────────────┘        │ └──────────────────┘ │
                          └──────────────────────┘
```

## Layer 1: MCP server

The server speaks MCP protocol over stdio (JSON-RPC) and registers tools via `ListTools` and `CallTool` handlers. The tool registry covers approximately 40-45 tools spanning command execution, templates, pipelines, workspace profiles, and Wave Terminal integration.

**Components**:
- `Server` initialisation with `StdioTransport`
- `CallTool` dispatch pattern (switch on tool name)
- `ListTools` handler returning tool descriptors with JSON Schema
- `MCPService` + `CommandReceiverService` lifecycle via `ServiceGroup`
- Logging via `swift-log`
- Configuration structure with a Wave-specific section
- Server name/version exposed in MCP handshake

## Layer 2: Wave config adapter

A new module responsible for reading and writing Wave Terminal's JSON configuration files.

**Target files** (all in `~/.waveterm/`):

| File | Purpose | Schema reference |
|------|---------|-----------------|
| `settings.json` | Global settings (AI, terminal, editor, window, app behaviour) | `/schema/settings.json` |
| `widgets.json` | Custom widget definitions with block metadata | `/schema/widgets.json` |
| `aipresets.json` | AI model presets (provider, model, tokens, API keys) | `/schema/aipresets.json` |
| `backgrounds.json` | Tab background definitions | `/schema/backgrounds.json` |
| `connections.json` | SSH connection configurations | `/schema/connections.json` |

**Design principles**:
- Read files with `JSONDecoder`, write with `JSONEncoder` (pretty-printed)
- Validate against Wave's JSON Schema before writing
- Preserve unknown keys (don't clobber user customisation)
- Create backups before writing (`.backup-{timestamp}`)
- File-level locking to prevent concurrent writes

**Key types**:

```swift
struct WaveConfigManager {
    let configDir: URL  // ~/.waveterm/

    func readSettings() throws -> WaveSettings
    func writeSettings(_ settings: WaveSettings) throws
    func readWidgets() throws -> [String: WidgetConfig]
    func writeWidgets(_ widgets: [String: WidgetConfig]) throws
    func readAIPresets() throws -> [String: AIPresetConfig]
    func writeAIPresets(_ presets: [String: AIPresetConfig]) throws
}
```

## Layer 3: Wave helper block

For operations that require `wsh` RPC access (block creation, scrollback retrieval, secrets), we deploy a lightweight helper that runs inside Wave.

**How it works**:

1. MCP server creates a Wave widget definition in `widgets.json` for the helper
2. User launches the helper widget in Wave (or it auto-launches)
3. Helper is a shell script or small binary that:
   - Has access to `WAVETERM_JWT`, `WAVETERM_BLOCKID`, `WAVETERM_TABID`
   - Opens a TCP listener on `localhost:{port}`
   - Accepts JSON-RPC requests from the MCP server
   - Translates them to `wsh` RPC calls via domain socket
   - Returns results

**Helper widget definition** (in widgets.json):

```json
{
  "seashell-helper": {
    "icon": "robot",
    "label": "Seashell Helper",
    "description": "Bridge between Claude MCP and Wave Terminal",
    "blockdef": {
      "meta": {
        "view": "term",
        "controller": "cmd",
        "cmd": "seashell-helper",
        "cmd:runonstart": true,
        "cmd:persistent": true,
        "cmd:closeonexit": false
      }
    }
  }
}
```

**Communication protocol** (helper ↔ MCP server):

```json
// Request
{"method": "wave.listWorkspaces", "id": 1}

// Response
{"result": [...], "id": 1}
```

**Helper scope**: The helper is intentionally simple. It wraps the `wsh` Go library calls or shells out to `wsh` (since it runs inside Wave, it has the JWT).

## Layer 4: command execution

**Components**:
- `executeCommandDirect()` – spawns `Process` with `/bin/bash -c`
- `CommandResultsStore` actor – in-memory result cache
- `AutoRetrieve` and `AutoRetrieveEnhanced` – intelligent polling
- `PipelineAndStreaming` – multi-step pipelines and streaming output
- `InteractiveCommandDetector` – safety classification
- Wave-block targeting (via helper) and Wave-specific context on `CommandRecord` (workspace ID, block ID)

## Layer 5: SQLite persistence

**Components**:
- `DatabaseManager.shared` singleton with barrier writes
- Tables: `commands` (with `wave_workspace_id` and `wave_block_id` columns), `templates`, `projects`, `wave_profiles`
- Integrity checking and auto-recovery
- Migration system for schema upgrades

## Layer 6: permission guard

New module that classifies each tool call by risk tier and enforces approval.

```swift
enum PermissionTier {
    case safe       // Tier A: log and proceed
    case confirm    // Tier B: return confirmation prompt, require second call
    case approve    // Tier C: return strong warning, require explicit "yes" with reason
}

struct PermissionGuard {
    func classify(tool: String, params: [String: Any]) -> PermissionTier
    func checkApproval(tool: String, approvalToken: String?) -> Bool
}
```

**Tier classification**:
- Reading anything → Tier A
- Writing config files, creating widgets, executing commands → Tier B
- Secrets, shell dotfiles, destructive operations → Tier C

## Configuration

The existing `Configuration` struct expands:

```swift
struct Configuration: Codable {
    // ... existing fields (terminal, security, output, history, logging, etc.)

    // New Wave-specific section
    var wave: WaveConfig

    struct WaveConfig: Codable {
        var configDir: String           // default: "~/.waveterm"
        var helperPort: Int             // default: 9877
        var helperEnabled: Bool         // default: false (phase 2)
        var backupBeforeWrite: Bool     // default: true
        var schemaValidation: Bool      // default: true
    }
}
```

**Location**: `~/.seashell/config.json`

## File layout (new and modified files)

```
Sources/Seashell/
├── Seashell.swift          - server entry point and tool registration
├── Configuration.swift                - configuration types and loading
├── PermissionGuard.swift              - tier-based permission system
├── MCPProtocolHandlers.swift          - protocol-level handlers
│
├── WaveConfigAdapter.swift            - read/write Wave JSON configs
├── WaveConfigTypes.swift              - Swift types for Wave schemas
├── WaveToolHandlers.swift             - direct config-file Wave tool handlers
├── WaveHelperClient.swift             - TCP client for the in-Wave helper
├── WaveHelperHandlers.swift           - helper-block tool handlers
├── WaveSecretsHandlers.swift           - secrets and workspace handlers
│
├── CommandHandlers.swift              - command execution handlers
├── CommandHandlersStable.swift        - stable subset of execution handlers
├── CommandReceiverService.swift       - TCP receiver for in-Wave input
├── CommandSuggestionEngine.swift      - command suggestion engine
├── CommandHistory.swift               - history queries
├── PendingCommands.swift              - pending-command tracking
├── AutoRetrieve.swift                 - intelligent output polling
├── AutoRetrieveEnhanced.swift         - polling with structured parsers
├── PipelineAndStreaming.swift         - multi-step pipelines and streaming
├── OutputParsers.swift                - command-output parsers
│
├── EnvironmentContext.swift           - runtime/project detection
├── EnvironmentSnapshot.swift          - environment capture/diff
├── HealthAndHistory.swift             - health checks and history tools
├── WorkspaceProfiles.swift            - workspace profile system
│
├── TerminalConfig.swift               - terminal type detection
├── TerminalSessions.swift             - terminal session management
├── TerminalUtilities.swift            - terminal helpers
├── ClipboardBridge.swift              - clipboard integration
├── FileWatcher.swift                  - filesystem watch tools
├── NotificationSupport.swift          - macOS notification helpers
├── SSHExecution.swift                 - SSH execution tools
│
└── Database/
    ├── DatabaseManager.swift          - SQLite layer (commands, templates, profiles)
    ├── DatabaseManager+Analytics.swift - usage analytics
    └── DatabaseModels.swift           - row types

Sources/ConfigManager/
└── main.swift                         - standalone config-management binary
```

## MCP tool surface

### Tier 1 tools (direct Wave config + execution)

**Wave config reading:**
- `wave_get_settings` – read full or filtered settings.json
- `wave_get_widgets` – list all widget definitions
- `wave_get_ai_presets` – list AI model presets
- `wave_get_backgrounds` – list background definitions

**Wave config writing:**
- `wave_set_setting` – update a settings.json key
- `wave_create_widget` – add a widget to widgets.json
- `wave_update_widget` – modify an existing widget
- `wave_delete_widget` – remove a widget
- `wave_set_ai_preset` – create or update an AI preset
- `wave_set_theme` – set terminal theme (term:theme in settings)
- `wave_set_appearance` – set window/terminal appearance settings

**Command execution:**
- `execute_command` – run command, capture output
- `execute_with_auto_retrieve` – run with intelligent polling
- `execute_with_streaming` – stream output in real time
- `execute_pipeline` – multi-step command pipeline
- `get_command_output` – retrieve stored output
- `list_recent_commands` – command history

**Templates and profiles:**
- `save_template` / `run_template` / `list_templates`
- `save_workspace_profile` / `load_workspace_profile` / `list_workspace_profiles`

**Environment:**
- `get_environment_context` – detect runtimes, git, project type
- `capture_environment` / `diff_environment`

### Tier 2 tools (via in-Wave helper block)

- `wave_list_workspaces` – list workspaces with metadata
- `wave_list_blocks` – list blocks with filtering
- `wave_create_block` – create a new block (term, preview, web, etc.)
- `wave_delete_block` – remove a block
- `wave_get_scrollback` – get terminal scrollback from a block
- `wave_run_in_block` – execute command in a new Wave block
- `wave_view_file` – open file preview in Wave
- `wave_edit_file` – open file for editing in Wave
- `wave_set_block_meta` – update block metadata
- `wave_get_block_meta` – read block metadata

### Secrets, backgrounds, and workspace tools

- `wave_secret_list` – list secret names
- `wave_secret_set` – set a secret (Tier C)
- `wave_secret_get` – retrieve a secret (Tier C)
- `wave_secret_delete` – delete a secret (Tier C)
- `wave_set_background` – set tab background image or colour
- `wave_create_fish_widget` – create fish-configured widget
- `wave_bootstrap_workspace` – apply a project workspace template

## Wave Terminal's object model (reference)

Wave's object hierarchy:

```
Window
  └── Workspace (has name, icon, colour)
        └── Tab (has background, preset)
              └── Block (the fundamental unit)
                    ├── view: "term" | "preview" | "web" | "sysinfo" | "waveai" | "launcher"
                    ├── controller: "shell" | "cmd"
                    ├── meta: key-value metadata
                    └── files: embedded file content
```

**Block meta keys** (from Wave source, used in widgets.json and wsh):
- `view` – block type
- `controller` – "shell" (interactive) or "cmd" (run command)
- `cmd` – command to execute
- `cmd:cwd` – working directory
- `cmd:env` – environment variables
- `cmd:runonstart` – auto-run on block creation
- `cmd:runonce` – run only once
- `cmd:closeonexit` – close block when command finishes
- `cmd:persistent` – keep block alive
- `cmd:shell` – use shell to interpret command
- `cmd:initscript.{shell}` – shell-specific init script
- `term:fontsize`, `term:fontfamily`, `term:theme` – terminal appearance
- `term:localshellpath`, `term:localshellopts` – shell configuration
- `file` – file path for preview/edit blocks
- `url` – URL for web blocks

**Settings key namespaces** (from settings.json schema):
- `app:*` – application behaviour
- `ai:*` – AI model configuration
- `waveai:*` – Wave AI specific settings
- `term:*` – terminal defaults
- `editor:*` – editor settings
- `web:*` – web view settings
- `window:*` – window appearance
- `tab:*` – tab defaults
- `widget:*` – widget behaviour
- `conn:*` – connection settings
- `telemetry:*` – telemetry
- `autoupdate:*` – auto-update

**wsh RPC mechanism**:
- Domain socket communication (not HTTP)
- JWT authentication via `WAVETERM_JWT` environment variable
- Block context via `WAVETERM_BLOCKID` and `WAVETERM_TABID`
- All wsh commands require this environment (they cannot run outside Wave)
