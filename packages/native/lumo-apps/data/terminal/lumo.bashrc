# SPDX-FileCopyrightText: 2026 Lumo Developers
# SPDX-License-Identifier: GPL-2.0-or-later

[ -f /etc/bash.bashrc ] && . /etc/bash.bashrc
[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"

export TEXTDOMAIN=lumo-terminal

__lumo_t() {
    gettext -d lumo-terminal "$1" 2>/dev/null || printf '%s' "$1"
}

__lumo_ignore_case() {
    local value=true line
    if [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/lumo-terminalrc" ]; then
        while IFS= read -r line; do
            case "$line" in IgnoreCase=*) value=${line#IgnoreCase=} ;; esac
        done < "${XDG_CONFIG_HOME:-$HOME/.config}/lumo-terminalrc"
    fi
    [ "$value" = "$__lumo_case" ] && return
    __lumo_case=$value
    if [ "$value" = true ]; then
        bind 'set completion-ignore-case on' 2>/dev/null
        shopt -s nocaseglob
    else
        bind 'set completion-ignore-case off' 2>/dev/null
        shopt -u nocaseglob
    fi
}

__lumo_find_folder() {
    local path=$1 result part match entry
    case "$path" in
        /*) result=/ ;;
        *) result=. ;;
    esac
    local IFS=/
    for part in $path; do
        [ -z "$part" ] && continue
        if [ -d "$result/$part" ]; then
            result="$result/$part"
            continue
        fi
        match=""
        for entry in "$result"/*/ "$result"/.*/; do
            entry=${entry%/}
            entry=${entry##*/}
            if [ "${entry,,}" = "${part,,}" ]; then
                match=$entry
                break
            fi
        done
        [ -z "$match" ] && return 1
        result="$result/$match"
    done
    printf '%s' "${result#./}"
}

cd() {
    if [ "$__lumo_case" = true ] && [ $# -eq 1 ] && [ -n "$1" ] && [ "$1" != - ] && [ ! -d "$1" ]; then
        local found
        if found=$(__lumo_find_folder "$1"); then
            builtin cd -- "$found"
            return
        fi
    fi
    builtin cd "$@"
}

__lumo_prompt() {
    local status=$?
    __lumo_ignore_case
    printf '\033]7;file://%s%s\033\\' "${HOSTNAME:-localhost}" "$PWD"
    printf '\033]0;%s\007' "${PWD/#$HOME/\~}"
    __lumo_mark=""
    [ "$status" -ne 0 ] && __lumo_mark="\[\033[31m\]✕ $status \[\033[0m\]"
    PS1="${__lumo_mark}\[\033[1;34m\]\w\[\033[0m\]\[\033[1;33m\]>\[\033[0m\] "
}

case ";${PROMPT_COMMAND};" in
    *";__lumo_prompt;"*) ;;
    *) PROMPT_COMMAND="__lumo_prompt${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac

alias cls='clear'
alias dir='ls -la --color=auto --group-directories-first'
alias copy='cp -i'
alias xcopy='cp -ri'
alias move='mv -i'
alias ren='mv -i'
alias rename='mv -i'
alias del='rm -i'
alias erase='rm -i'
alias md='mkdir -p'
alias rd='rmdir'
alias type='cat'
alias cd..='cd ..'
alias ipconfig='ip -c -br address'
alias tasklist='ps -e -o pid,user,%cpu,%mem,comm --sort=-%cpu'
alias where='which -a'
alias tree='find . -not -path "*/.*" | sort | sed -e "s;[^/]*/;  ;g"'
alias findstr='grep --color=auto'
alias systeminfo='hostnamectl'
alias start='xdg-open'
alias explorer='xdg-open .'
alias notepad='lumo-editor'
alias calc='lumo-calculator'
alias taskmgr='lumo-taskmanager'

taskkill() {
    local target=""
    while [ $# -gt 0 ]; do
        case "$1" in
            /pid|/PID|-pid) shift; kill "$1"; return ;;
            /im|/IM|-im) shift; target="$1" ;;
            /f|/F|-f) ;;
            *) target="$1" ;;
        esac
        shift
    done
    [ -n "$target" ] && pkill -x "${target%.exe}"
}

ver() {
    local name
    name=$(. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-Lumo}")
    printf '%s, Linux %s\n' "$name" "$(uname -r)"
}

help() {
    if [ $# -gt 0 ]; then
        builtin help "$@"
        return
    fi
    printf '\n  \033[1m%s\033[0m\n\n' "$(__lumo_t 'Windows commands you can use here')"
    while IFS='|' read -r command linux meaning; do
        printf '  \033[1;33m%-10s\033[0m \033[34m%-12s\033[0m %s\n' "$command" "$linux" "$(__lumo_t "$meaning")"
    done <<'TABLE'
dir|ls|List the files in this folder
cd|cd|Go to another folder (cd .. goes up)
cls|clear|Clear the screen
copy|cp|Copy a file
move|mv|Move a file
ren|mv|Rename a file
del|rm|Delete a file
md|mkdir|Make a folder
rd|rmdir|Remove an empty folder
type|cat|Show what is in a file
findstr|grep|Search for text
ipconfig|ip address|Show the network addresses
tasklist|ps|Show the running programs
taskkill|pkill|Stop a program
where|which|Find where a program is
ver|uname|Show the version of the system
start|xdg-open|Open a file or folder with its app
TABLE
    printf '\n  %s\n\n' "$(__lumo_t 'Run a command as administrator by putting sudo in front of it.')"
}

if [ -z "$LUMO_TERMINAL_GREETED" ]; then
    export LUMO_TERMINAL_GREETED=1
    printf '\033[2m%s\033[0m\n\n' "$(__lumo_t 'Type help to see the Windows commands you can use.')"
fi
