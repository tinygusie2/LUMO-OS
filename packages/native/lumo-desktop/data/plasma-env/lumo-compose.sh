if [ -z "${XCOMPOSEFILE:-}" ] && [ ! -e "$HOME/.XCompose" ] && [ ! -e "${XDG_CONFIG_HOME:-$HOME/.config}/XCompose" ]; then
    export XCOMPOSEFILE=/usr/share/lumo/XCompose
fi
