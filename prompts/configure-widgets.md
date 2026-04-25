# Design your Wave widget set

Wave Terminal widgets are pinned shortcuts in the sidebar that launch a block when clicked — a terminal, a system monitor, a file viewer, a web view, etc. Paste this prompt to have your AI design a widget set around the things *you* check every day.

---

## Prompt to paste

I'm using Wave Terminal and want to design my widget bar. A widget is a `widgets.json` entry like:

```json
{
  "widget-id": {
    "icon": "phosphor-icon-name",
    "color": "#hex",
    "label": "Display Name",
    "description": "What this widget does",
    "blockdef": {
      "meta": {
        "view": "term",
        "controller": "cmd",
        "cmd": "the command to run",
        "cmd:cwd": "/path/to/start/dir",
        "cmd:runonstart": true,
        "cmd:persistent": true,
        "cmd:env": { "VAR": "value" }
      }
    }
  }
}
```

Available `view` types:
- `term` — runs a command in a new terminal block (most common)
- `preview` — opens a file for viewing (set `meta.file` to the path)
- `web` — embedded web view (set `meta.url`)
- `sysinfo` — system stats panel

Available controllers:
- `cmd` — runs a one-shot command (with `cmd:runonstart: true` to auto-start)
- `shell` — opens an interactive shell

Wave uses Phosphor icon names — see https://phosphoricons.com for the catalog (use the kebab-case name, e.g. `chart-bar`, `terminal`, `git-branch`, `database`, `robot`).

### Things I look at most

- **Daily**: <fill in: e.g. "logs of my dev server", "git status of my main project", "my GitHub PRs", "btop", "Slack">
- **Weekly**: <fill in: e.g. "my time-tracking spreadsheet", "deploy dashboard">
- **At session start** (auto-launch on Wave open): <fill in: e.g. "fish in ~/Github", "btop">

### Tools I have installed

<fill in or write "the standard set: git, fish, ollama, btop, lazygit, glances, fastfetch">

### Projects I switch between

<fill in directory paths or describe: e.g. "my-app at ~/Github/my-app", "client-x at ~/Work/client-x">

### Things I deliberately don't want as widgets

<fill in: e.g. "no email — I don't want it in the terminal" / "no music — I have a separate app for that">

### Output

Give me:
1. **5–8 widgets** — `widgets.json` blocks, ready to paste into `~/.config/waveterm/widgets.json`
2. For each: a one-line rationale tying it to what I told you
3. A suggested icon name from Phosphor and a hex color (use a coherent palette — pick a base color and vary hue)
4. Optionally: which 1–2 widgets should auto-launch on Wave open (set `cmd:runonstart: true` and pin to the workspace)

Don't include widgets I didn't ask for. If something I mentioned doesn't fit a widget (e.g., "checking Slack" is better as the Slack app), say so and skip it.
