function __llm_predict
    set -l current (commandline)
    set -l prefetch_file /tmp/fish_llm_prefetch

    # If commandline is empty, serve the pre-fetched prediction instantly
    if test -z "$current" -a -f $prefetch_file
        set -l cached (cat $prefetch_file 2>/dev/null)
        rm -f $prefetch_file
        if test -n "$cached"
            commandline $cached
            commandline -f repaint
            return
        end
    end

    if test -z "$current"
        return
    end

    # Commandline has content — complete/convert what's there
    commandline "$current ⏳"
    commandline -f repaint

    set -l hist (builtin history | head -8 | string join " | ")
    set -l payload (python3 -c "
import json, sys
current, cwd, hist = sys.argv[1], sys.argv[2], sys.argv[3]
msg = f'CWD: {cwd}. Recent: {hist}. The user typed: \"{current}\". Complete or convert to the best shell command. Output ONLY the raw command.'
print(json.dumps({
    'model': 'qwen2.5-coder:1.5b', 'stream': False,
    'messages': [
        {'role': 'system', 'content': 'Complete or predict shell commands. Output ONLY the raw command. No backticks, no explanation.'},
        {'role': 'user',   'content': msg}
    ]
}))
" "$current" "$PWD" "$hist" 2>/dev/null)

    set -l suggestion (curl -s --max-time 8 http://localhost:11434/api/chat \
        -H "content-type: application/json" -d $payload 2>/dev/null \
        | python3 -c "
import sys,json
try:
    r=json.load(sys.stdin)['message']['content'].strip().strip('\`').strip()
    print(r.splitlines()[0])
except: print('')
" 2>/dev/null)

    if test -n "$suggestion"
        commandline $suggestion
    else
        commandline $current
    end
    commandline -f repaint
end
