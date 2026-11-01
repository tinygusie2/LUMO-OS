#!/usr/bin/env bash
set -Eeuo pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
package_root="$project_root/packages/native/lumo-quickshare"
package_version=$(dpkg-parsechangelog -l"$package_root/debian/changelog" -S Version)
deb="$project_root/_build/binary-packages/lumo-quickshare_${package_version}_amd64.deb"

fail() {
  printf 'lumo-quickshare binary test: %s\n' "$*" >&2
  exit 1
}

[[ -s "$deb" ]] || fail "binary package does not exist: $deb"
[[ "$(dpkg-deb --field "$deb" Architecture)" == "amd64" ]] || fail "wrong architecture"
[[ "$(dpkg-deb --field "$deb" Version)" == "$package_version" ]] || fail "wrong version"
for dependency in bluez libdbus-1-3 wl-clipboard; do
  dpkg-deb --field "$deb" Depends | grep -Eq "(^|, )$dependency( |,|$)" \
    || fail "missing dependency: $dependency"
done

temporary_root=$(mktemp -d /tmp/lumo-quickshare-test.XXXXXX)
trap 'find "$temporary_root" -depth -delete' EXIT
dpkg-deb --extract "$deb" "$temporary_root"

[[ -x "$temporary_root/usr/bin/lumo-quickshare" ]] || fail "missing the daemon"
for path in usr/share/applications/org.lumo.quickshare.desktop \
  etc/xdg/autostart/org.lumo.quickshare-autostart.desktop \
  usr/share/dbus-1/services/org.lumo.QuickShare.service \
  usr/share/doc/lumo-quickshare/LICENSES.txt \
  usr/share/doc/lumo-quickshare/copyright; do
  [[ -s "$temporary_root/$path" ]] || fail "missing $path"
done
grep -q '^rqs_lib ' "$temporary_root/usr/share/doc/lumo-quickshare/LICENSES.txt" \
  || fail "the license list does not cover rqs_lib"
if grep -q 'AGPL' "$temporary_root/usr/share/doc/lumo-quickshare/LICENSES.txt"; then
  fail "an AGPL crate is linked in"
fi
grep -aq 'org.lumo.QuickShare1' "$temporary_root/usr/bin/lumo-quickshare" \
  || fail "the daemon does not export its D-Bus interface"

printf 'lumo-quickshare binary test: OK\n'
