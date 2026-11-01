#!/bin/sh
config=${XDG_CONFIG_HOME:-$HOME/.config}
data=${XDG_DATA_HOME:-$HOME/.local/share}
entry="$data/applications/org.lumo.welcome.desktop"
if grep -q '^ShowOnLogin=false' "$config/lumo-welcomerc" 2>/dev/null && [ ! -e "$entry" ]; then
  mkdir -p "$data/applications"
  printf '[Desktop Entry]\nType=Application\nName=Welcome\nIcon=org.lumo.welcome\nExec=lumo-welcome\nNoDisplay=true\n' > "$entry"
fi
exit 0
