if status is-interactive
    # Auto-start Seashell Helper invisibly when inside Wave Terminal.
    # Inherits WAVETERM_SWAPTOKEN from fish so it can exchange for JWT,
    # but runs as a detached background process with no visible block.
    if set -q WAVETERM; and not lsof -i:9877 -sTCP:LISTEN >/dev/null 2>&1
        /usr/bin/python3 $HOME/.local/bin/seashell-helper >/dev/null 2>&1 &
        disown
    end

    # System info banner on new shell
    if command -q fastfetch
        fastfetch
    end

    if command -q zoxide
        zoxide init fish | source
    end

    # Option-F (⌥F) — fuzzy directory picker
    # Shows a fuzzy-searchable dropdown of subdirs (and frecent dirs from zoxide).
    # Arrow keys to navigate, Enter to cd, Esc to cancel.
    function __fzf_cd
        set -l dir (
            # Combine current subdirs + zoxide frecent list, deduplicated
            begin
                fd --type d --max-depth 4 --hidden --exclude .git . 2>/dev/null
                zoxide query --list 2>/dev/null
            end | sort -u | fzf \
                --height 40% \
                --layout reverse \
                --border rounded \
                --prompt "  cd  " \
                --preview 'ls -la {}' \
                --preview-window right:40%
        )
        if test -n "$dir"
            cd $dir
            commandline -f repaint
        end
    end
    bind alt-f __fzf_cd

    # Alt-Space — LLM command prediction
    # Start typing anything (partial command or natural language), press ⌥Space,
    # and the local model completes or converts it to a full command.
    bind alt-space __llm_predict

    # Enter key — NL-aware: intercepts unknown commands before fish can emit [127]
    bind enter __nl_enter
    if bind -M insert >/dev/null 2>&1
        bind -M insert enter __nl_enter
    end
end
