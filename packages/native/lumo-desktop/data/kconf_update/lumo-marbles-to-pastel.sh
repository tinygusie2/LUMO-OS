#!/bin/sh
file="${XDG_CONFIG_HOME:-$HOME/.config}/kscreenlockerrc"
if [ -f "$file" ] && grep -q 'org\.lumo\.marbles' "$file"; then
  sed -i 's/^\([Ww]allpaper[Pp]lugin=\)org\.lumo\.marbles$/\1org.lumo.pastel/' "$file"
fi
exit 0
