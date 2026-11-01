#!/usr/bin/env bash
set -Eeuo pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
package_root="$project_root/packages/native/lumo-base"

fail() {
  printf 'lumo-base source test: %s\n' "$*" >&2
  exit 1
}

for dependency in dpkg-parsechangelog grep; do
  command -v "$dependency" >/dev/null 2>&1 \
    || fail "required command not found: $dependency"
done

version=$(dpkg-parsechangelog -l"$package_root/debian/changelog" -S Version)
distribution=$(dpkg-parsechangelog \
  -l"$package_root/debian/changelog" -S Distribution)
[[ "$version" == "1.6.5" ]] || fail "unexpected source version"
[[ "$distribution" == "UNRELEASED" ]] \
  || fail "development package must remain UNRELEASED"
[[ "$(<"$package_root/debian/source/format")" == "3.0 (native)" ]] \
  || fail "wrong source format"
[[ -x "$package_root/debian/rules" ]] || fail "debian/rules is not executable"

control="$package_root/debian/control"
grep -Fxq 'Package: lumo-base' "$control" || fail "binary stanza is missing"
grep -Fxq 'Architecture: all' "$control" || fail "package is not architecture-all"
grep -Fxq 'Section: admin' "$control" || fail "wrong archive section"
grep -Fxq 'Standards-Version: 4.7.4' "$control" \
  || fail "wrong Standards-Version"
grep -Fxq ' base-files (= 13.8+deb13u7+lumo1),' "$control" \
  || fail "base-files dependency is not pinned to the Lumo build"
grep -Eq '^ lumo-archive \(>= 1\.6\),?$' "$control" \
  || fail "the package archives are not part of the base system"
if grep -Eq '^(Essential|Protected|Pre-Depends|Priority):' "$control"; then
  fail "base package declares an inappropriate control field"
fi

for tool in git curl wget htop fastfetch unzip zip 7zip; do
  grep -Fxq " $tool," "$package_root/debian/control" || grep -Fxq " $tool" "$package_root/debian/control" || fail "lumo-base does not bring $tool"
done

fastfetch="$package_root/data/fastfetch"
[[ -s "$fastfetch/lumo.txt" && -s "$fastfetch/lumo-small.txt" ]] || fail "the fastfetch logos are missing"
! grep -Fq '$' "$fastfetch/lumo.txt" "$fastfetch/lumo-small.txt" || fail "a logo has a \$ that fastfetch reads as a colour code"
grep -Fq '"source": "/usr/share/lumo/fastfetch/lumo.txt"' "$fastfetch/config.jsonc" \
  && grep -Fq '"source": "/usr/share/lumo/fastfetch/lumo-small.txt"' "$fastfetch/lumo-small.jsonc" \
  || fail "fastfetch does not use the Lumo logo"
grep -Fq '"modules": [' "$fastfetch/config.jsonc" && grep -Fq '"modules": [' "$fastfetch/lumo-small.jsonc" \
  || fail "fastfetch 2.40 prints only the logo without a module list"
grep -Fxq 'data/fastfetch/config.jsonc etc/xdg/fastfetch' "$package_root/debian/lumo-base.install" \
  || fail "the fastfetch config is not installed"

printf 'lumo-base source test: OK\n'
