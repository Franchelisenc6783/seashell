# tools.fish — modern CLI replacements and integrations

# ── eza (modern ls) ───────────────────────────────────────────────────────────
if command -q eza
    abbr --add ls  'eza --icons --group-directories-first'
    abbr --add ll  'eza --icons --group-directories-first -la'
    abbr --add lt  'eza --icons --tree --level=2'
    abbr --add ltt 'eza --icons --tree --level=3'
end

# ── bat (modern cat) ──────────────────────────────────────────────────────────
if command -q bat
    abbr --add cat 'bat'
    # bat as man pager — man pages get syntax highlighting
    set -gx MANPAGER "sh -c 'col -bx | bat -l man -p'"
end

# ── lazygit ───────────────────────────────────────────────────────────────────
if command -q lazygit
    abbr --add lg 'lazygit'
end

# ── yazi (file manager) — Option-Y to open, exits into the dir you navigated to
if command -q yazi
    function y
        set -l tmp (mktemp -t yazi-cwd)
        yazi $argv --cwd-file=$tmp
        if set -l cwd (cat $tmp 2>/dev/null); and test -n "$cwd"; and test "$cwd" != "$PWD"
            cd $cwd
        end
        rm -f $tmp
    end
    bind alt-y 'y; commandline -f repaint'
end

# ── direnv (auto-load .env per project) ───────────────────────────────────────
if command -q direnv
    direnv hook fish | source
end

# ── tldr (practical man pages) ────────────────────────────────────────────────
if command -q tldr
    abbr --add h 'tldr'
end
