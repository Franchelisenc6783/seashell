# wave-theme.fish — auto-switch Wave theme on every new terminal tab
# Runs inside Wave where WAVETERM_JWT is available, so wsh setconfig works.

if set -q WAVETERM_JWT
    set -l wsh "$HOME/Library/Application Support/waveterm/bin/wsh"
    set -l dark_mode (defaults read -g AppleInterfaceStyle 2>/dev/null)
    if test "$dark_mode" = "Dark"
        "$wsh" setconfig 'term:theme=dracula' 2>/dev/null
    else
        "$wsh" setconfig 'term:theme=github-light' 2>/dev/null
    end
end
