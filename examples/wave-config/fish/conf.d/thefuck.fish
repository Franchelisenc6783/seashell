# thefuck — command autocorrection
# After a failed command, press Option-Enter (⌥↩) to autocorrect and rerun.
# Or just type: fuck

if command -q thefuck
    thefuck --alias | source

    # Bind Option-Enter to run 'fuck' instantly
    function __run_thefuck
        set -l cmd (thefuck (history | head -1) 2>/dev/null)
        if test -n "$cmd"
            commandline $cmd
            commandline -f execute
        end
    end
    bind alt-enter __run_thefuck
end
