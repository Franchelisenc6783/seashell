function ai --description "Natural language → shell command. Usage: ai open my documents folder"
    if test (count $argv) -eq 0
        echo "Usage: ai <what you want to do>"
        echo "Example: ai open my documents folder"
        return 1
    end

    set -l query (string join " " $argv)
    set -l api_key $ANTHROPIC_API_KEY

    if test -z "$api_key"
        echo "❌ ANTHROPIC_API_KEY not set. Add it to ~/.config/fish/conf.d/secrets.fish"
        return 1
    end

    set -l os_context "macOS, fish shell, cwd: $PWD"
    set -l payload (printf '{"model":"claude-haiku-4-5-20251001","max_tokens":256,"messages":[{"role":"user","content":"You are a shell command generator. The user is on %s. Respond with ONLY the shell command, no explanation, no markdown, no backticks. If multiple commands are needed use && or semicolons. Query: %s"}]}' "$os_context" "$query")

    echo "⏳ Thinking..."

    set -l response (curl -s https://api.anthropic.com/v1/messages \
        -H "x-api-key: $api_key" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d $payload 2>/dev/null)

    set -l cmd (echo $response | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d['content'][0]['text'].strip())
except:
    print('')
" 2>/dev/null)

    if test -z "$cmd"
        echo "❌ Could not get a response. Check your API key and connection."
        return 1
    end

    # Show the suggested command and put it in the prompt for editing
    echo ""
    echo "  $cmd"
    echo ""
    read --prompt-str "  Run it? [Y/n/e to edit] " --local confirm

    switch $confirm
        case '' Y y
            eval $cmd
        case e E
            commandline $cmd
        case '*'
            echo "Cancelled."
    end
end
