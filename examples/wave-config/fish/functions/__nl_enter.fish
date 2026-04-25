function __nl_enter --description 'Enter key handler: NL routing with spinner + typewriter animations'
    set -l cmdline (commandline -b)
    set -l trimmed (string trim -- $cmdline)

    # Empty → just submit
    if test -z "$trimmed"
        commandline -f execute
        return
    end

    # Strip trailing backslashes (tab-completion artifact)
    set -l trimmed (string replace -r '\\+$' '' -- $trimmed)
    set -l trimmed (string trim -- $trimmed)

    # Extract first token
    set -l first (string split -m1 ' ' -- $trimmed)[1]

    # Strip leading env-var assignments (FOO=bar cmd → check "cmd")
    while string match -q -- '*=*' $first
        set -l rest (string replace -r '^[^=]+=\S*\s*' '' -- $trimmed)
        set trimmed (string trim -- $rest)
        if test -z "$trimmed"; break; end
        set first (string split -m1 ' ' -- $trimmed)[1]
    end

    # ── Natural language detection ────────────────────────────────────────────
    # Shell commands never contain English articles, possessives, or linking
    # words — so their presence is a reliable NL signal.
    set -l words (string split ' ' -- (string lower -- $trimmed))
    set -l word_count (count $words)
    set -l has_flags (string match -qr -- '(^| )-[a-zA-Z]' $trimmed; and echo yes; or echo no)

    set -l is_nl false

    # Rule 1: ends with ?
    if string match -q -- '*?' $trimmed
        set is_nl true
    end

    # Rule 2: starts with a question word
    if contains -- $words[1] what which who why when where how
        set is_nl true
    end

    # Rule 3: contains English function words that never appear in raw shell commands
    if not $is_nl; and test $word_count -gt 1; and test "$has_flags" = no
        set -l nl_markers \
            the an this that these those \
            my your our their its \
            me him her us them myself yourself \
            is are was were been being \
            have has had will would could should may might must \
            please help want need about
        for w in $words
            if contains -- $w $nl_markers
                set is_nl true
                break
            end
        end
    end

    # Rule 4: action word that doubles as a command (make, copy…) + prose (no flags, 3+ words)
    if not $is_nl; and test $word_count -gt 2; and test "$has_flags" = no
        if contains -- $words[1] make duplicate rename tell explain describe give
            set is_nl true
        end
    end

    # Known command/function/builtin → normal execute (unless detected as NL)
    if not $is_nl; and type -q -- $first 2>/dev/null
        commandline $trimmed
        commandline -f execute
        return
    end

    # ── Path shortcut: "Documents/" or "~/foo/bar/" → cd directly ────────────
    # Avoids Ollama entirely for simple directory navigation
    if string match -q -- '*/' $trimmed
        commandline ''
        commandline -f repaint
        if cd -- $trimmed 2>/dev/null
            return 0
        end
        # cd failed — fall through to Ollama so it can suggest the right path
    end

    # Ollama not running → fall through to normal execute
    if not curl -s --max-time 1 http://localhost:11434 >/dev/null 2>&1
        commandline $trimmed
        commandline -f execute
        return
    end

    # ── Setup ─────────────────────────────────────────────────────────────────
    set -l original_query $trimmed
    set -l query_parts (string split ' ' -- $trimmed)
    commandline ''
    commandline -f repaint
    echo ""

    set -l frames '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'

    # ── Spinner while Ollama classifies + generates ───────────────────────────
    set -l tmp_out /tmp/nl_out_{$fish_pid}
    python3 ~/.config/fish/nl_handler.py $PWD $query_parts >$tmp_out 2>/dev/null &
    set -l nl_pid $last_pid

    set -l f 1
    while kill -0 $nl_pid 2>/dev/null
        set_color brblue
        printf "\r  %s  thinking..." $frames[$f]
        set_color normal
        set f (math \( $f % (count $frames) \) + 1)
        sleep 0.08
    end
    wait $nl_pid 2>/dev/null
    printf "\r\033[2K"

    set -l result (cat $tmp_out 2>/dev/null)
    rm -f $tmp_out

    if test -z "$result"
        set_color red; printf "  ✗  No response\n"; set_color normal
        echo ""
        return 0
    end

    # ── General knowledge answer ──────────────────────────────────────────────
    if string match -q -- 'QUESTION:*' $result
        set -l answer (string replace -- 'QUESTION:' '' $result)
        set_color yellow; printf "  ℹ  "; set_color normal
        set_color yellow
        for ch in (string split '' -- $answer)
            printf "%s" $ch
            sleep 0.015
        end
        set_color normal
        echo ""

        # If the answer contains a backtick command, offer to run it
        set -l suggested (string match -r -- '`[^`]+`' $answer | string replace -a -- '`' '')
        if test -n "$suggested"
            echo ""
            set_color brblack; printf "  run "; set_color normal
            set_color cyan; printf "%s" $suggested; set_color normal
            set_color brblack; printf "? [Enter / Ctrl+C]  "; set_color normal
            read -P '' -l confirm
            echo ""
            if test $status -eq 0
                eval $suggested
            end
        end

        echo ""
        return 0
    end

    # ── Shell command ─────────────────────────────────────────────────────────
    if string match -q -- 'COMMAND:*' $result
        # Strip any trailing backslash the model may have emitted
        set -l cmd (string replace -- 'COMMAND:' '' $result)
        set -l cmd (string replace -r '\\+$' '' -- $cmd)
        set -l cmd (string trim -- $cmd)

        # Typewriter reveal of command
        set_color cyan; printf "  ➜  "; set_color normal
        set_color cyan
        for ch in (string split '' -- $cmd)
            printf "%s" $ch
            sleep 0.022
        end
        set_color normal
        echo ""

        # Confirm before running
        set_color brblack; printf "     run? [Enter / Ctrl+C]  "; set_color normal
        read -P '' -l confirm
        echo ""

        # Run the command
        eval $cmd
        set -l exit_code $status

        # ── On success only: one-line explanation ─────────────────────────────
        if test $exit_code -eq 0
            set -l tmp_exp /tmp/nl_exp_{$fish_pid}

            python3 -c "
import json, subprocess, sys, re
q, c = sys.argv[1], sys.argv[2]
payload = json.dumps({'model':'qwen2.5-coder:1.5b','stream':False,'keep_alive':'30m','messages':[
    {'role':'system','content':'Explain shell commands in ONE sentence of max 12 words. No bullet points. No newlines. Output only that one sentence.'},
    {'role':'user','content':f'Command: {c}'}]})
r = subprocess.run(['curl','-s','--max-time','8','http://localhost:11434/api/chat',
    '-H','content-type: application/json','-d',payload],capture_output=True,text=True)
out = json.loads(r.stdout)['message']['content'].strip()
first = re.split(r'(?<=[.!?])\s', out)[0]
print(first[:120])
" "$original_query" "$cmd" >$tmp_exp 2>/dev/null &
            set -l exp_pid $last_pid

            set -l f 1
            echo ""
            while kill -0 $exp_pid 2>/dev/null
                set_color bryellow
                printf "\r  %s  " $frames[$f]
                set_color normal
                set f (math \( $f % (count $frames) \) + 1)
                sleep 0.08
            end
            wait $exp_pid 2>/dev/null
            printf "\r\033[2K"

            set -l explanation (cat $tmp_exp 2>/dev/null)
            rm -f $tmp_exp

            if test -n "$explanation"
                set_color yellow; printf "  ℹ  "; set_color normal
                set_color yellow
                for ch in (string split '' -- $explanation)
                    printf "%s" $ch
                    sleep 0.012
                end
                set_color normal
                echo ""
            end
        end

        echo ""
        return $exit_code
    end

    # Unrecognised response → restore and execute normally
    commandline $original_query
    commandline -f execute
end
