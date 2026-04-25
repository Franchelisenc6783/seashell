# Install on a fresh Mac

Paste this prompt into your AI assistant after filling in the placeholders. The assistant will walk you through installing Seashell, Wave Terminal, fish, and Ollama from scratch on a clean macOS machine.

---

## Prompt to paste

I have a fresh Mac and want to set up Seashell (https://github.com/M-Pineapple/seashell) — an MCP server bridging Claude Desktop and Wave Terminal — along with the recommended shell stack.

Walk me through every step, in order, with copy-paste commands:

1. **Xcode Command Line Tools** — `xcode-select --install`
2. **Homebrew** — paste the official curl install line and add the post-install PATH setup
3. **Brew packages** — give me a single `brew install` line covering:
   - Required: `fish`, `python@3.12`, `ollama`
   - Recommended: `atuin`, `starship`, `zoxide`, `direnv`, `fastfetch`, `eza`, `bat`, `fd`, `fzf`, `lazygit`, `thefuck`, `git-delta`, `tldr`, `gh`
   - Optional: `btop`, `yazi`, `jbreckmckye/formulae/daylight`
4. **Make fish my default shell** — `chsh -s /opt/homebrew/bin/fish` and add it to `/etc/shells` if needed
5. **Wave Terminal** — give me the brew cask command or the direct download link from waveterm.dev
6. **Claude Desktop** — give me the install link from claude.ai/download
7. **Ollama model** — `ollama pull qwen2.5-coder:1.5b` (or the right size for my RAM — see below)
8. **Clone Seashell** — `git clone https://github.com/M-Pineapple/seashell ~/Github/seashell`
9. **Build Seashell** — `cd ~/Github/seashell && ./build.sh`
10. **Register with Claude Desktop** — show me the exact `~/Library/Application Support/Claude/claude_desktop_config.json` patch
11. **Restart Claude Desktop** — and tell me how to verify Seashell tools are visible
12. **(Optional) Install the example wave-config** — `cd examples/wave-config && ./install.sh`

For each step, tell me:
- **What success looks like** — what to see in the terminal / what to test
- **What to do if it fails** — common error and the fix

Here's my Mac:

- **CPU**: <fill in: Apple Silicon (M1/M2/M3/M4) or Intel>
- **macOS version**: <fill in: e.g. Sonoma 14.5, Sequoia 15.0>
- **RAM**: <fill in: e.g. 16GB, 32GB, 64GB>
- **Free disk space**: <fill in: e.g. 100GB free>

Use my RAM to recommend the right Ollama model:
- 8–16GB → `qwen2.5-coder:1.5b` (1GB)
- 16–32GB → `qwen2.5-coder:7b` (4.5GB)
- 64GB+ → `qwen2.5-coder:32b` (20GB)

Don't ask me which I want — recommend the appropriate one based on my RAM, and only suggest swapping if I push back.
