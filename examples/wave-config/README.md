# Wave Terminal example config

An opinionated, working starter for [Wave Terminal](https://github.com/wavetermdev/waveterm) with [fish shell](https://fishshell.com/), local-LLM-powered command prediction, and auto theme switching. **Optional** — Seashell works fine without any of this. This bundle is just *one* way to set up Wave nicely.

If you want a setup tailored to **your** taste rather than someone else's, see [`prompts/`](../../prompts/) — those let your AI assistant configure Wave from scratch based on what you tell it.

---

## What's in here

```
examples/wave-config/
├── install.sh                     ← run this to install everything
│
├── fish/
│   ├── config.fish                ← top-level fish config: keybindings, fastfetch banner, helper auto-start
│   ├── nl_handler.py              ← classifies queries as SHELL/QUESTION and generates commands via Ollama
│   ├── conf.d/
│   │   ├── atuin.fish             ← shell history (⌥-R)
│   │   ├── git.fish               ← git abbreviations (gs, ga, gc, gp, …)
│   │   ├── secrets.fish.template  ← API key template — copy + fill in
│   │   ├── thefuck.fish           ← command autocorrection (⌥-Enter)
│   │   ├── tools.fish             ← eza/bat/lazygit/yazi/direnv/tldr integrations
│   │   ├── uv.env.fish            ← sources ~/.local/bin/env.fish if present
│   │   └── wave-theme.fish        ← per-tab theme switch on Wave
│   └── functions/
│       ├── __llm_predict.fish     ← ⌥-Space: complete or convert what you typed
│       ├── __llm_prefetch.fish    ← background prediction after each command
│       ├── __nl_enter.fish        ← Enter key handler with NL detection + spinner + typewriter
│       ├── __notify_long_command.fish  ← macOS notification on commands > 10s
│       ├── ai.fish                ← `ai <query>` → Anthropic API → command
│       ├── cd.fish                ← cd + auto-list with eza
│       ├── extract.fish           ← extract any archive (`x file.tar.gz`)
│       ├── fish_command_not_found.fish
│       ├── mkcd.fish              ← mkdir + cd in one
│       ├── port.fish              ← `port 9876` → who's listening
│       └── up.fish                ← `up 3` → cd ../../../
│
├── fastfetch/
│   └── config.jsonc               ← system info banner shown on every new shell
│
├── wave/
│   ├── widgets.template.json      ← btop monitor, Seashell Helper, fish dev, daylight widgets
│   └── settings.template.json     ← font, cursor, transparency, theme defaults
│
└── theme-sync/
    ├── wave-theme-sync                          ← Python script: light↔dark by macOS appearance
    └── dev.seashell.theme-sync.plist.template   ← LaunchAgent (runs theme-sync every 30s)
```

---

## Prerequisites

Install these before running `install.sh`:

```bash
# Required
brew install fish python@3.12 ollama

# Recommended (the fish config detects them at runtime — missing ones are skipped)
brew install atuin starship zoxide direnv fastfetch \
             eza bat fd fzf git-delta lazygit tldr thefuck

# Optional widgets
brew install btop
brew install jbreckmckye/formulae/daylight   # for the daylight widget

# Pull the local LLM model (1.5GB)
ollama pull qwen2.5-coder:1.5b
```

For 64GB+ machines, swap the model to `qwen2.5-coder:32b` for higher-quality predictions:

```bash
ollama pull qwen2.5-coder:32b
# Then change the MODEL constant in:
#   ~/.config/fish/nl_handler.py
#   ~/.config/fish/functions/__llm_predict.fish
#   ~/.config/fish/functions/__llm_prefetch.fish
```

---

## Install

```bash
cd examples/wave-config
./install.sh
```

The installer:
1. Backs up your existing `~/.config/fish/` to `~/.config/fish.backup-<timestamp>`
2. Installs fish config to `~/.config/fish/`
3. Installs fastfetch config to `~/.config/fastfetch/config.jsonc`
4. Copies `wave-theme-sync` to `~/.local/bin/`
5. Generates and loads `~/Library/LaunchAgents/dev.seashell.theme-sync.plist`
6. Leaves Wave's own configs (`~/.config/waveterm/`) untouched — those need manual merging

---

## Wave config templates

The Wave config files (`~/.config/waveterm/widgets.json`, `settings.json`) are user-personal — overwriting them would clobber your existing widgets and presets. Instead, the templates here are reference material:

```bash
# Open the templates and your live config side by side
open examples/wave-config/wave/
open ~/.config/waveterm/
```

Then merge whatever you want into your real Wave config files. Wave watches its config files and reloads on change, so saving the file applies immediately.

---

## Keyboard shortcuts (after install)

| Key                    | Action |
|------------------------|--------|
| `Enter` (NL detected)  | Routes to local LLM, classifies SHELL vs QUESTION, runs/answers with confirmation |
| `⌥-Space`              | Predict / complete the current command line via Ollama |
| `⌥-F`                  | Fuzzy directory picker (subdirs + zoxide frecent) |
| `⌥-R`                  | Atuin shell history search (replaces Ctrl-R) |
| `⌥-Y`                  | Open yazi file manager |
| `⌥-Enter`              | Run `thefuck` to auto-correct your last command |
| `ai <query>`           | Same as the local NL handler but using Anthropic API instead |
| `extract foo.tar.gz`   | Extract any archive format (also: `x foo.tar.gz`) |
| `port 9876`            | Show what process is using a port |
| `mkcd new-dir`         | Create + cd into a directory |
| `up 3`                 | `cd ../../../` |

---

## How the NL Enter key actually works

`__nl_enter.fish` intercepts every Enter press in interactive fish and decides:

1. **Empty line** → submit normally
2. **Looks like a real command** (first token resolves via `type -q`, no NL markers) → run normally
3. **Path-like with trailing `/`** → try `cd` directly
4. **Otherwise** → send to `nl_handler.py` (Ollama), which:
   - Classifies as SHELL or QUESTION
   - For SHELL: generates a command, shows it with a typewriter animation, waits for confirmation
   - For QUESTION: answers in 1–3 sentences with a typewriter reveal
5. After a successful SHELL command, requests a one-line plain-English explanation

Triggers for NL routing:
- Ends with `?`
- Starts with `what`/`which`/`who`/`why`/`when`/`where`/`how`
- Contains English function words (`the`, `my`, `is`, `please`, `want`, etc.)
- Action verbs (`make`, `duplicate`, `rename`, `tell`) followed by 2+ prose words

If the first token is already a known command (`ls`, `git`, etc.), NL routing is skipped — your normal commands run instantly.

---

## Theme auto-switching

The LaunchAgent runs `wave-theme-sync` every 30 seconds:
- macOS in **Dark mode** → Wave terminal theme: `dracula`
- macOS in **Light mode** → Wave terminal theme: `github-light`

Manage it:

```bash
# Disable
launchctl unload ~/Library/LaunchAgents/dev.seashell.theme-sync.plist

# Re-enable
launchctl load -w ~/Library/LaunchAgents/dev.seashell.theme-sync.plist

# Logs
tail -f /tmp/wave-theme-sync.log
```

---

## Troubleshooting

**fastfetch banner doesn't show on new shell**: Confirm `command -q fastfetch` returns true (`fastfetch --version`) and that `~/.config/fastfetch/config.jsonc` exists.

**`__nl_enter` doesn't trigger NL on prose**: Check Ollama is running (`curl http://localhost:11434`) and the model is pulled (`ollama list`).

**`ai` function says "ANTHROPIC_API_KEY not set"**: Edit `~/.config/fish/conf.d/secrets.fish` and add a real key from https://console.anthropic.com/settings/keys.

**Theme sync not switching**: Check `tail -f /tmp/wave-theme-sync.log` and verify the plist loaded with `launchctl list | grep seashell`.

**Helper widget shows red**: The helper auto-start in `config.fish` looks for it at `$HOME/.local/bin/seashell-helper`. Either install Seashell's helper there, or update the path in `config.fish` line 6.

**Brew installed somewhere else** (Intel Mac / custom prefix): The fish files use `command -q toolname` so they auto-detect. The Wave `settings.template.json` hardcodes `/opt/homebrew/bin/fish` because Wave needs an absolute path — change it to `/usr/local/bin/fish` for Intel Macs.

---

## Uninstall

```bash
# Stop and remove the LaunchAgent
launchctl unload ~/Library/LaunchAgents/dev.seashell.theme-sync.plist
rm ~/Library/LaunchAgents/dev.seashell.theme-sync.plist

# Remove the script
rm ~/.local/bin/wave-theme-sync

# Restore your old fish config (if you had one)
mv ~/.config/fish ~/.config/fish.removed
mv ~/.config/fish.backup-<timestamp> ~/.config/fish
```
