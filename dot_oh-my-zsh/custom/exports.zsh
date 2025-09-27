export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

export GOPATH="$HOME/go"
export GOBIN="$GOPATH/bin"

export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'

export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"