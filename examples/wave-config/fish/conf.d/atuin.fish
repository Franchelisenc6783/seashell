# atuin — shell history search
# filter_mode = "directory" should be set in ~/.config/atuin/config.toml
# Bound to Option-R (⌥R) — atuin's default Ctrl-R is removed.

if command -q atuin
    atuin init fish | source

    # Move atuin from Ctrl-R to Option-R
    bind --erase ctrl-r
    bind alt-r _atuin_search
    if bind -M insert >/dev/null 2>&1
        bind --erase -M insert ctrl-r
        bind -M insert alt-r _atuin_search
    end
end
