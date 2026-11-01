#!/usr/bin/env bash
set -Eeuo pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
package_root="$project_root/packages/native/lumo-archive"

fail() {
  printf 'lumo-archive source test: %s\n' "$*" >&2
  exit 1
}

for dependency in dpkg-parsechangelog grep; do
  command -v "$dependency" >/dev/null 2>&1 \
    || fail "required command not found: $dependency"
done
# shellcheck disable=SC1091
source "$project_root/configs/project.env"

[[ "$(dpkg-parsechangelog -l"$package_root/debian/changelog" -S Version)" == "1.4" ]] \
  || fail "unexpected source version"
[[ "$(dpkg-parsechangelog -l"$package_root/debian/changelog" -S Distribution)" == "UNRELEASED" ]] \
  || fail "development package must remain UNRELEASED"
[[ "$(<"$package_root/debian/source/format")" == "3.0 (native)" ]] || fail "wrong source format"
[[ -x "$package_root/debian/rules" ]] || fail "debian/rules is not executable"

control="$package_root/debian/control"
grep -Fxq 'Package: lumo-archive' "$control" || fail "binary stanza is missing"
grep -Fxq 'Architecture: all' "$control" || fail "package is not architecture-all"
for dependency in debian-archive-keyring unattended-upgrades; do
  grep -Fxq " $dependency" "$control" || grep -Fxq " $dependency," "$control" \
    || fail "missing dependency: $dependency"
done

apt="$package_root/apt"
grep -Fxq 'URIs: https://deb.debian.org/debian' "$apt/debian.sources" || fail "no Debian archive"
grep -Fxq 'Suites: trixie-security' "$apt/debian.sources" || fail "no Debian security updates"
grep -Fxq 'Suites: trixie-backports' "$apt/debian.sources" || fail "no trixie-backports for the kernel and Mesa"
for source in src:linux src:linux-signed-amd64 src:firmware-nonfree src:mesa src:libdrm; do
  grep -q "^Package: .*$source\( \|$\)" "$apt/lumo-backports.pref" || fail "$source is not taken from trixie-backports"
done
grep -Fxq 'Pin: release n=trixie-backports' "$apt/lumo-backports.pref" || fail "the backports pin names no release"
grep -Fq '"origin=Debian Backports,codename=trixie-backports,label=Debian Backports";' "$apt/51lumo-unattended-upgrades" \
  || fail "kernel updates from trixie-backports are not installed automatically"
if grep -rq 'snapshot.debian.org' "$apt"; then
  fail "the installed system must not use the build snapshot"
fi
[[ ! -e "$apt/lumo.sources" ]] || fail "lumo.sources points at an archive Lumo does not publish yet"
if grep -rqi 'commywork9282-dotcom\|kernora' "$package_root/apt" "$package_root/debian/lumo-archive.install"; then
  fail "the installed system must not update from the upstream Kernora archive"
fi
grep -Fxq 'Package: base-files calamares polkit-kde-agent-1' "$apt/lumo-archive.pref" \
  && grep -Fxq 'Pin: version *lumo*' "$apt/lumo-archive.pref" \
  && grep -Fxq 'Pin-Priority: 1000' "$apt/lumo-archive.pref" \
  || fail "Debian could replace Lumo's own builds of Debian packages"
grep -Fq '"origin=Debian,codename=trixie-security,label=Debian-Security";' "$apt/51lumo-unattended-upgrades" \
  || fail "security updates are not installed automatically"
grep -Fxq 'APT::Periodic::Unattended-Upgrade "1";' "$apt/21lumo-auto-upgrades" \
  || fail "unattended upgrades are not enabled"
for timer in apt-daily apt-daily-upgrade; do
  grep -Fxq 'ConditionKernelCommandLine=!boot=live' "$package_root/systemd/$timer.timer.d/lumo-live.conf" \
    || fail "$timer runs in the live session"
done

printf 'lumo-archive source test: OK\n'
