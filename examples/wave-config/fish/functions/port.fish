function port --description 'Show what process is using a port'
    if test (count $argv) -eq 0
        echo "Usage: port <number>"
        return 1
    end
    lsof -i :"$argv[1]" -sTCP:LISTEN,ESTABLISHED
end
