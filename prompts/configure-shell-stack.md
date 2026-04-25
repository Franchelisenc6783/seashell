# Choose your shell stack

Paste this prompt to have your AI guide you through choosing fish vs zsh, picking the right Ollama model for your RAM, and selecting which fish plugins/tools to install.

---

## Prompt to paste

I'm setting up Seashell (https://github.com/M-Pineapple/seashell) — an MCP server bridging Claude Desktop and Wave Terminal — and need to choose a shell stack that fits my workflow.

Help me decide on each of these. Be opinionated; don't list every option without picking.

### 1. Shell

- **fish** — modern, syntax highlighting and autosuggestions out of the box, less compatible with bash scripts
- **zsh** — system default on macOS, vast plugin ecosystem (oh-my-zsh, zinit), more bash-compatible
- **leave system default** — minimal change, slowest path to nice features

### 2. History tool

- **atuin** — encrypted cross-machine sync, fuzzy search, scoped per-directory; binds ⌥-R
- **fish/zsh built-ins** — no setup, no sync, fewer features

### 3. Prompt

- **starship** — cross-shell, fast (<1ms), tasteful defaults; works with fish and zsh
- **powerlevel10k** — zsh only, dense info, instant prompt
- **default** — fastest, minimal info

### 4. Local LLM (Ollama, for the natural-language Enter key)

| Model | Size | Speed | Quality | Recommended RAM |
|---|---|---|---|---|
| `qwen2.5-coder:1.5b` | ~1GB | Very fast | Basic | 8–16GB |
| `qwen2.5-coder:7b` | ~4.5GB | Fast | Good | 16–32GB |
| `qwen2.5-coder:32b` | ~20GB | Slower | Excellent | 64GB+ |

### 5. Modern CLI tools

Pick a sensible subset. Each has aliases that replace the legacy command:

- **eza** (`ls`), **bat** (`cat`), **fd** (`find`), **rg** (`grep`)
- **fzf** (fuzzy finder, drives ⌥-F), **zoxide** (smart cd that learns frecent dirs)
- **lazygit** (TUI for git), **tldr** (short man pages)
- **thefuck** (auto-correct your last command on ⌥-Enter)
- **direnv** (auto-load `.env` per project), **yazi** (TUI file manager)

Plus optional widgets / decoration:
- **btop** (system monitor), **fastfetch** (banner on shell open)
- **glances** (richer system info), **daylight** (sunrise/sunset widget)

### My machine + workflow

- **Mac model + RAM**: <fill in: e.g. M3 Pro, 36GB>
- **Free disk**: <fill in>
- **I spend most time on**: <fill in: e.g. "Python data work", "Rust services", "frontend with npm", "ops/devops">
- **Comfort with terminal**: <fill in: novice / intermediate / power user>
- **Existing terminal customizations**: <fill in or "none">
- **Things I'd love automated**: <fill in: e.g. "remembering deploy commands", "navigating between 6 repos">
- **Things I want to keep manual**: <fill in: e.g. "git operations — I want to see what I'm doing">

### Output

Give me:

1. **Recommended stack** — one line per choice with one-line rationale
2. **Brew install command** — single `brew install …` line
3. **Ollama pull command** — for the right model size
4. **Config snippets** — fish or zsh, ready to paste

Be decisive. If my workflow strongly suggests something, recommend it without listing alternatives.
