#!/usr/bin/env bash
set -Eeuo pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
package_root="$project_root/packages/native/lumo-base"
package_version=$(dpkg-parsechangelog -l"$package_root/debian/changelog" -S Version)
deb="$project_root/_build/binary-packages/lumo-base_${package_version}_all.deb"

fail() {
  printf 'lumo-base binary test: %s\n' "$*" >&2
  exit 1
}

for dependency in cmp dpkg-deb find grep; do
  command -v "$dependency" >/dev/null 2>&1 \
    || fail "required command not found: $dependency"
done

[[ -s "$deb" ]] || fail "binary package does not exist"
[[ "$(dpkg-deb --field "$deb" Package)" == "lumo-base" ]] \
  || fail "wrong package name"
[[ "$(dpkg-deb --field "$deb" Version)" == "$package_version" ]] \
  || fail "wrong package version"
[[ "$(dpkg-deb --field "$deb" Architecture)" == "all" ]] \
  || fail "wrong package architecture"
[[ "$(dpkg-deb --field "$deb" Section)" == "admin" ]] \
  || fail "wrong package section"
depends=$(dpkg-deb --field "$deb" Depends)
[[ "$depends" == "base-files (= 13.8+deb13u7+lumo1), lumo-archive (>= 1.6), 7zip, bash-completion, curl, fastfetch, git, htop, iw, lsof, man-db, openssh-client, pciutils, rsync, tree, unzip, usbutils, wget, zip" ]] \
  || fail "wrong binary dependency: $depends"
essential=$(dpkg-deb --field "$deb" Essential)
[[ "$essential" == "no" || -z "$essential" ]] \
  || fail "base package must not be Essential"

temporary_root=$(mktemp -d /tmp/lumo-base-test.XXXXXX)
trap 'find "$temporary_root" -depth -delete' EXIT
dpkg-deb --extract "$deb" "$temporary_root/root"
if find "$temporary_root/root" -type f \
  ! -path "$temporary_root/root/usr/share/doc/lumo-base/*" \
  ! -path "$temporary_root/root/usr/share/lumo/workarounds/20-lumo-rtl8852ce.conf" \
  ! -path "$temporary_root/root/usr/share/lumo/fastfetch/lumo.txt" \
  ! -path "$temporary_root/root/usr/share/lumo/fastfetch/lumo-small.txt" \
  ! -path "$temporary_root/root/etc/xdg/fastfetch/config.jsonc" \
  ! -path "$temporary_root/root/usr/share/fastfetch/presets/lumo-small.jsonc" \
  -print -quit | grep -q .; then
  fail "base package contains an unexpected file"
fi
cmp "$package_root/data/NetworkManager/20-lumo-rtl8852ce.conf" \
  "$temporary_root/root/usr/share/lumo/workarounds/20-lumo-rtl8852ce.conf" \
  || fail "optional RTL8852CE example is missing or changed during packaging"
[[ ! -e "$temporary_root/root/usr/lib/NetworkManager/conf.d/20-lumo-rtl8852ce.conf" ]] \
  || fail "withdrawn RTL8852CE policy is still automatically enabled"

for logo in lumo.txt lumo-small.txt; do
  cmp "$package_root/data/fastfetch/$logo" "$temporary_root/root/usr/share/lumo/fastfetch/$logo" \
    || fail "fastfetch logo $logo is missing or changed during packaging"
done
cmp "$package_root/data/fastfetch/config.jsonc" "$temporary_root/root/etc/xdg/fastfetch/config.jsonc" \
  && cmp "$package_root/data/fastfetch/lumo-small.jsonc" "$temporary_root/root/usr/share/fastfetch/presets/lumo-small.jsonc" \
  || fail "fastfetch config is missing or changed during packaging"

dpkg-deb --control "$deb" "$temporary_root/control"
grep -Fxq '/etc/xdg/fastfetch/config.jsonc' "$temporary_root/control/conffiles" \
  || fail "the fastfetch config is not a conffile"
[[ -x "$temporary_root/control/postinst" ]] || fail "root ownership migration is missing"
grep -Fq 'chown 0:0 /' "$temporary_root/control/postinst" \
  || fail "upgrade does not repair root ownership"

printf 'lumo-base binary test: OK\n'
