#!/usr/bin/env bash
# install.sh — install the Seashell example wave-config
#
# What this does:
#   1. Snapshots existing fish AND Wave configs into ~/.seashell-backups/<timestamp>/
#   2. Stops any conflicting LaunchAgents (e.g., older theme-sync variants)
#   3. Copies fish/, fastfetch/, theme-sync/ files into your $HOME
#   4. Generates a LaunchAgent plist with your real $HOME path and loads it
#   5. Does NOT overwrite Wave widgets.json or settings.json — you merge those manually
#   6. Does NOT install any brew packages — install those yourself first
#
# Required brew packages (install before running):
#   fish ollama atuin starship zoxide direnv fastfetch
#   eza bat fd fzf git-delta lazygit tldr thefuck
#   jbreckmckye/formulae/daylight   (optional — for the daylight widget)
#
# Required ollama models:
#   ollama pull qwen2.5-coder:1.5b
#
# Run with:
#   cd examples/wave-config && ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/.seashell-backups/$TIMESTAMP"

say()  { printf '\033[36m▶\033[0m %s\n' "$*"; }
warn() { printf '\033[33m⚠\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }

# ── Pre-flight checks ────────────────────────────────────────────────────────
command -v fish >/dev/null 2>&1     || { warn "fish not found — install with 'brew install fish'"; exit 1; }
command -v python3 >/dev/null 2>&1  || { warn "python3 not found — required for nl_handler.py and theme-sync"; exit 1; }

# ── 0. Snapshot everything we might touch ────────────────────────────────────
say "Creating safety snapshot at $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

if [ -d "$HOME/.config/fish" ]; then
    cp -R "$HOME/.config/fish" "$BACKUP_DIR/fish"
    ok "fish config snapshotted"
fi

if [ -d "$HOME/.config/waveterm" ]; then
    mkdir -p "$BACKUP_DIR/waveterm"
    for f in settings.json widgets.json aipresets.json backgrounds.json connections.json; do
        if [ -f "$HOME/.config/waveterm/$f" ]; then
            cp "$HOME/.config/waveterm/$f" "$BACKUP_DIR/waveterm/$f"
        fi
    done
    ok "Wave config snapshotted (settings/widgets/aipresets/backgrounds/connections)"
fi

if [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then
    mkdir -p "$BACKUP_DIR/fastfetch"
    cp "$HOME/.config/fastfetch/config.jsonc" "$BACKUP_DIR/fastfetch/config.jsonc"
    ok "fastfetch config snapshotted"
fi

# ── 0.5. Stop any older LaunchAgent that runs wave-theme-sync ───────────────
# Detects any plist (not ours) that references wave-theme-sync and unloads it
# so the new dev.seashell.theme-sync agent doesn't race with an older one.
for old_plist in "$HOME"/Library/LaunchAgents/*.plist; do
    [ -f "$old_plist" ] || continue
    grep -q "wave-theme-sync" "$old_plist" 2>/dev/null || continue
    grep -q "dev.seashell.theme-sync" "$old_plist" 2>/dev/null && continue   # skip our own
    label=$(basename "$old_plist" .plist)
    warn "Found older theme-sync LaunchAgent: $label — unloading to avoid conflict"
    launchctl unload "$old_plist" 2>/dev/null || true
    cp "$old_plist" "$BACKUP_DIR/$label.plist"
    rm "$old_plist"
    ok "Old LaunchAgent unloaded and backed up"
done

# ── 2. Install fish files ────────────────────────────────────────────────────
say "Installing fish config to ~/.config/fish/"
mkdir -p "$HOME/.config/fish/conf.d" "$HOME/.config/fish/functions"
cp "$SCRIPT_DIR/fish/config.fish"      "$HOME/.config/fish/config.fish"
cp "$SCRIPT_DIR/fish/nl_handler.py"    "$HOME/.config/fish/nl_handler.py"

# conf.d (everything except the secrets template)
for f in "$SCRIPT_DIR/fish/conf.d"/*.fish; do
    cp "$f" "$HOME/.config/fish/conf.d/$(basename "$f")"
done

# secrets template — only install if user doesn't already have one
if [ ! -f "$HOME/.config/fish/conf.d/secrets.fish" ]; then
    cp "$SCRIPT_DIR/fish/conf.d/secrets.fish.template" "$HOME/.config/fish/conf.d/secrets.fish"
    warn "Installed secrets.fish — edit it and add your API keys: ~/.config/fish/conf.d/secrets.fish"
else
    ok "secrets.fish already exists — left unchanged"
fi

# functions
for f in "$SCRIPT_DIR/fish/functions"/*.fish; do
    cp "$f" "$HOME/.config/fish/functions/$(basename "$f")"
done
ok "fish config installed"

# ── 3. Install fastfetch config ──────────────────────────────────────────────
say "Installing fastfetch config to ~/.config/fastfetch/"
mkdir -p "$HOME/.config/fastfetch"
cp "$SCRIPT_DIR/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
ok "fastfetch config installed"

# ── 4. Install wave-theme-sync ──────────────────────────────────────────────
say "Installing wave-theme-sync to ~/.local/bin/"
mkdir -p "$HOME/.local/bin"
cp "$SCRIPT_DIR/theme-sync/wave-theme-sync" "$HOME/.local/bin/wave-theme-sync"
chmod +x "$HOME/.local/bin/wave-theme-sync"
ok "wave-theme-sync installed"

# ── 5. Install LaunchAgent ──────────────────────────────────────────────────
say "Installing LaunchAgent (auto theme switching every 30s)"
plist_dest="$HOME/Library/LaunchAgents/dev.seashell.theme-sync.plist"

# If already loaded, unload first
if launchctl list | grep -q "dev.seashell.theme-sync"; then
    launchctl unload "$plist_dest" 2>/dev/null || true
fi

# Replace REPLACE_HOME with the real $HOME and write
sed "s|REPLACE_HOME|$HOME|g" \
    "$SCRIPT_DIR/theme-sync/dev.seashell.theme-sync.plist.template" \
    > "$plist_dest"

launchctl load -w "$plist_dest"
ok "LaunchAgent loaded — Wave will auto-theme-switch from now on"

# ── Done ────────────────────────────────────────────────────────────────────
echo
ok "Install complete!"
echo
echo "Backups: $BACKUP_DIR"
echo "If anything breaks, restore with:"
echo "  rm -rf ~/.config/fish && cp -R '$BACKUP_DIR/fish' ~/.config/fish"
echo
cat <<EOF
Next steps:

  1. Edit ~/.config/fish/conf.d/secrets.fish with your real API keys.

  2. (Optional) Merge Wave config templates into your existing Wave settings:
       $SCRIPT_DIR/wave/widgets.template.json
       $SCRIPT_DIR/wave/settings.template.json
     Live Wave files live at ~/.config/waveterm/
     Your current Wave configs are snapshotted at $BACKUP_DIR/waveterm/

  3. Restart fish:
       exec fish

  4. Pull the local LLM (if you haven't):
       ollama pull qwen2.5-coder:1.5b

  5. Open Wave Terminal — fastfetch greets you, ⌥-Space predicts, Enter does NL.
EOF
