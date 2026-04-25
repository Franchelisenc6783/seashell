function extract --description 'Extract any archive — x file.tar.gz'
    if test (count $argv) -eq 0
        echo "Usage: extract <file> [file ...]"
        return 1
    end
    for file in $argv
        if not test -f $file
            echo "extract: '$file' is not a file"
            continue
        end
        switch $file
            case '*.tar.bz2' '*.tbz2'
                tar xjf $file
            case '*.tar.gz' '*.tgz'
                tar xzf $file
            case '*.tar.xz'
                tar xJf $file
            case '*.tar.zst'
                tar --zstd -xf $file
            case '*.tar'
                tar xf $file
            case '*.bz2'
                bunzip2 $file
            case '*.gz'
                gunzip $file
            case '*.xz'
                unxz $file
            case '*.zip'
                unzip $file
            case '*.Z'
                uncompress $file
            case '*.7z'
                7z x $file
            case '*.rar'
                unrar x $file
            case '*.dmg'
                hdiutil attach $file
            case '*'
                echo "extract: '$file' — unknown format"
        end
    end
end

abbr --add x extract
