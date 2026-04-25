# git.fish — git abbreviations

if command -q git
    abbr --add gs   'git status -sb'
    abbr --add ga   'git add'
    abbr --add gaa  'git add -A'
    abbr --add gc   'git commit -m'
    abbr --add gca  'git commit --amend'
    abbr --add gp   'git push'
    abbr --add gpl  'git pull'
    abbr --add gf   'git fetch --prune'
    abbr --add gco  'git checkout'
    abbr --add gcb  'git checkout -b'
    abbr --add gl   'git log --oneline --graph --decorate -20'
    abbr --add gd   'git diff'
    abbr --add gds  'git diff --staged'
    abbr --add grb  'git rebase'
    abbr --add gst  'git stash'
    abbr --add gstp 'git stash pop'
    abbr --add grst 'git reset --soft HEAD~1'
end
