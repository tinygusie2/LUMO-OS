case ":${XDG_CONFIG_DIRS:-}:" in
    *:/usr/share/lumo/xdg:*) ;;
    *) export XDG_CONFIG_DIRS="/usr/share/lumo/xdg:${XDG_CONFIG_DIRS:-/etc/xdg}" ;;
esac
