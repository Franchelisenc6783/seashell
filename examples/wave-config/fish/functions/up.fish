function up --description 'Go up N directories (default 1)'
    set -l n (test -n "$argv[1]"; and echo $argv[1]; or echo 1)
    cd (string repeat -n $n "../")
end
