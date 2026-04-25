# llm-warmup.fish — keep qwen2.5-coder:1.5b hot for natural-language routing
#
# Why: cold-loading a 1.5B-parameter model takes ~25s on M1, but
# nl_handler.py's per-call timeouts are sub-15s. Result: the very first
# Enter on a freshly-opened terminal silently times out and falls through
# to "fish: Unknown command: How". This snippet warms the model in the
# background as soon as fish becomes interactive, so by the time you've
# read the fastfetch banner, qwen is resident and replies in <1s.
#
# Idempotent: a sentinel at /tmp/seashell-llm-warmed-$USER suppresses
# re-warming for 5 minutes. Multiple Wave tabs opening together don't
# re-trigger.
#
# Off-switch: set SEASHELL_NO_LLM_WARMUP=1 in your environment.

if not status is-interactive
    exit 0
end

if test "$SEASHELL_NO_LLM_WARMUP" = 1
    exit 0
end

set -l sentinel /tmp/seashell-llm-warmed-$USER
set -l should_warm true

if test -f $sentinel
    # macOS uses `stat -f %m`, Linux uses `stat -c %Y`. Try both.
    set -l mtime (stat -f %m $sentinel 2>/dev/null; or stat -c %Y $sentinel 2>/dev/null; or echo 0)
    set -l age (math (date +%s) - $mtime)
    if test $age -lt 300
        set should_warm false
    end
end

if not $should_warm
    exit 0
end

# Cheap probe — is Ollama listening at all? Skip warmup if not.
if not curl -s --max-time 1 http://localhost:11434 >/dev/null 2>&1
    exit 0
end

touch $sentinel

# Fire-and-forget: tiny "hi" chat with keep_alive=30m pins the model in
# RAM for 30 minutes after this call returns (regardless of subsequent
# idle time). Total cost: ~25s the FIRST time, ~1s thereafter.
curl -s --max-time 60 http://localhost:11434/api/chat \
    -H 'content-type: application/json' \
    -d '{"model":"qwen2.5-coder:1.5b","stream":false,"keep_alive":"30m","messages":[{"role":"user","content":"hi"}]}' \
    >/dev/null 2>&1 &
disown
