function cd --wraps=cd --description 'cd with auto-list'
    builtin cd $argv
    and begin
        if command -q eza
            eza --icons --group-directories-first
        else
            ls
        end
    end
end
