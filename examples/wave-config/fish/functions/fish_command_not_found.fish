function fish_command_not_found
    # This fires in non-interactive contexts (scripts, subshells) where __nl_enter
    # isn't active. In interactive shells, bind enter __nl_enter handles NL routing
    # before fish ever reaches this function.
    echo "fish: Unknown command: $argv[1]" >&2
    return 127
end
