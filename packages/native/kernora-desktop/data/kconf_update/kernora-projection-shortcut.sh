#!/bin/sh
if command -v kwriteconfig6 >/dev/null 2>&1; then
  kwriteconfig6 --file kglobalshortcutsrc --group kscreen --key display "$(printf 'none,Display\tMeta+P,Switch Display')"
fi
exit 0
