#!/bin/sh
file="${XDG_CONFIG_HOME:-$HOME/.config}/kscreenlockerrc"
if [ -f "$file" ] && grep -q 'org\.lumo\.tower' "$file"; then
  sed -i 's/^\([Ww]allpaper[Pp]lugin=\)org\.lumo\.tower$/\1org.lumo.shapes/' "$file"
fi
exit 0
