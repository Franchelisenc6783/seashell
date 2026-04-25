function __llm_prefetch --on-event fish_postexec
    # Fire-and-forget background prefetch after every command.
    # Stores the predicted next command in /tmp/fish_llm_prefetch so
    # Alt-Space can serve it instantly without waiting.
    set -l cwd $PWD
    set -l hist (builtin history | head -8 | string join " | ")

    python3 -c "
import subprocess, json, sys, os

payload = json.dumps({
    'model': 'qwen2.5-coder:1.5b',
    'stream': False,
    'keep_alive': '30m',
    'messages': [
        {'role': 'system', 'content': 'Predict the single most likely next shell command the user will run. Output ONLY the raw command. Nothing else.'},
        {'role': 'user',   'content': f'CWD: {sys.argv[1]}. Recent commands: {sys.argv[2]}. What next?'}
    ]
})
try:
    r = subprocess.run(
        ['curl', '-s', '--max-time', '5', 'http://localhost:11434/api/chat',
         '-H', 'content-type: application/json', '-d', payload],
        capture_output=True, text=True, timeout=6
    )
    cmd = json.loads(r.stdout)['message']['content'].strip().strip('` ').splitlines()[0]
    with open('/tmp/fish_llm_prefetch', 'w') as f:
        f.write(cmd)
except:
    pass
" "$cwd" "$hist" &>/dev/null &

    disown
end
