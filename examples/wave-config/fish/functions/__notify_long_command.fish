function __notify_long_command --on-event fish_postexec \
    --description 'macOS notification when a command takes more than 10 seconds'
    # CMD_DURATION is in milliseconds
    if test $CMD_DURATION -gt 10000
        set -l label (string shorten -m 60 -- $argv[1])
        osascript -e "display notification \"$label\" with title \"Done ✓\" sound name \"Glass\"" 2>/dev/null
    end
end
