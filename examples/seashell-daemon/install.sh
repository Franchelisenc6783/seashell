#!/usr/bin/env bash
# install.sh — install the Seashell daemon as a LaunchAgent
#
# What this does:
#   1. Verifies `claude` CLI is installed (Claude Code)
#   2. Copies seashell-daemon to ~/.local/bin/
#   3. Generates the LaunchAgent plist with your $HOME baked in
#   4. Loads the LaunchAgent — it'll start now and on every login
#
# Uninstall:
#   launchctl unload ~/Library/LaunchAgents/dev.seashell.daemon.plist
#   rm ~/Library/LaunchAgents/dev.seashell.daemon.plist
#   rm ~/.local/bin/seashell-daemon

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say()  { printf '\033[36m▶\033[0m %s\n' "$*"; }
warn() { printf '\033[33m⚠\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
err()  { printf '\033[31m✗\033[0m %s\n' "$*" >&2; }

# ── Pre-flight: Claude Code ──────────────────────────────────────────────────
if ! command -v claude >/dev/null 2>&1; then
    err "claude CLI not found in PATH"
    echo ""
    echo "The Seashell daemon uses Claude Code (the 'claude' CLI) to respond"
    echo "to inbox messages. Install it from:"
    echo "  https://docs.claude.com/claude-code"
    echo ""
    echo "After install, run 'claude auth login' to authenticate via your"
    echo "Claude.ai subscription. Then re-run this installer."
    exit 1
fi
ok "claude CLI found at $(command -v claude)"

# Verify auth
if ! claude --version >/dev/null 2>&1; then
    warn "claude --version failed. You may need to run 'claude auth login'."
fi

# ── Pre-flight: Seashell MCP server registered with Claude Code? ─────────────
# Best-effort check — it's OK if we can't determine this.
if claude mcp list 2>/dev/null | grep -qi seashell; then
    ok "seashell MCP server is registered with Claude Code"
else
    warn "seashell MCP server may not be registered with Claude Code."
    warn "If the daemon's claude invocations can't see the tools, register with:"
    warn "  claude mcp add seashell <absolute-path-to>/seashell/.build/release/seashell"
fi

# ── 1. Install daemon binary ─────────────────────────────────────────────────
say "Installing seashell-daemon to ~/.local/bin/"
mkdir -p "$HOME/.local/bin"
cp "$SCRIPT_DIR/seashell-daemon" "$HOME/.local/bin/seashell-daemon"
chmod +x "$HOME/.local/bin/seashell-daemon"
ok "Installed"

# ── 2. Install LaunchAgent ───────────────────────────────────────────────────
say "Installing LaunchAgent"
plist="$HOME/Library/LaunchAgents/dev.seashell.daemon.plist"

# Stop existing
if launchctl list | grep -q "dev.seashell.daemon"; then
    say "Stopping existing daemon to reload"
    launchctl unload "$plist" 2>/dev/null || true
fi

sed "s|REPLACE_HOME|$HOME|g" \
    "$SCRIPT_DIR/dev.seashell.daemon.plist.template" \
    > "$plist"

launchctl load -w "$plist"
ok "LaunchAgent loaded — daemon is running and will auto-start on login"

# ── Done ────────────────────────────────────────────────────────────────────
echo ""
ok "Daemon install complete."
echo ""
cat <<EOF
Status:           launchctl list | grep dev.seashell.daemon
Live logs:        tail -f /tmp/seashell-daemon.log
Stop:             launchctl unload $plist
Manual run-once:  ~/.local/bin/seashell-daemon once

The daemon polls every ${SEASHELL_DAEMON_POLL:-5} seconds. Try it:

  cd ~/Github/seashell      # or any seashell-init'd project
  seashell-ask "what's the status?"

Within ~5–10s, the daemon picks up the message, runs claude in this
project's directory, and the reply unblocks your terminal.
EOF
