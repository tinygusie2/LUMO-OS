#!/usr/bin/env bash
set -Eeuo pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
package_root="$project_root/packages/native/lumo-archive"

fail() {
  printf 'lumo-archive source test: %s\n' "$*" >&2
  exit 1
}

for dependency in dpkg-parsechangelog gpg grep; do
  command -v "$dependency" >/dev/null 2>&1 \
    || fail "required command not found: $dependency"
done
# shellcheck disable=SC1091
source "$project_root/configs/project.env"

[[ "$(dpkg-parsechangelog -l"$package_root/debian/changelog" -S Version)" == "1.6" ]] \
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

[[ "$DIST_ARCHIVE_KEY_FINGERPRINT" =~ ^[0-9A-F]{40}$ ]] || fail "the archive key fingerprint is not set"
keyring="$package_root/keyrings/lumo-archive-keyring.asc"
gnupg_home=$(mktemp -d)
trap 'rm -rf -- "$gnupg_home"' EXIT
fingerprint=$(GNUPGHOME=$gnupg_home gpg --batch --quiet --show-keys --with-colons "$keyring" \
  | awk -F: '$1 == "fpr" && !seen { print $10; seen = 1 }')
[[ "$fingerprint" == "$DIST_ARCHIVE_KEY_FINGERPRINT" ]] || fail "the keyring is not the archive key"
grep -Fq 'BEGIN PGP PRIVATE KEY' "$keyring" && fail "the keyring holds a private key"

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
grep -Fxq 'Signed-By: /usr/share/keyrings/lumo-archive-keyring.asc' "$apt/lumo.sources" \
  || fail "the Lumo archive is not signed by its key"
lumo_uri=$(awk '/^URIs:/ { print $2 }' "$apt/lumo.sources")
[[ "$lumo_uri" == "$DIST_UPDATES_URL" ]] || fail "lumo.sources does not point at $DIST_UPDATES_URL"
lumo_host=${lumo_uri#https://}
lumo_host=${lumo_host%%/*}
grep -Fxq "Pin: origin $lumo_host" "$apt/lumo-archive.pref" \
  || fail "Lumo packages are not preferred over Debian's"
if grep -rqi 'commywork9282-dotcom\|kernora' "$package_root/apt" "$package_root/debian/lumo-archive.install"; then
  fail "the installed system must not update from the upstream Kernora archive"
fi
grep -Fxq 'Package: base-files calamares polkit-kde-agent-1' "$apt/lumo-archive.pref" \
  && grep -Fxq 'Pin: version *lumo*' "$apt/lumo-archive.pref" \
  && grep -Fxq 'Pin-Priority: 1000' "$apt/lumo-archive.pref" \
  || fail "Debian could replace Lumo's own builds of Debian packages"
demo_sources="$apt/lumo-demo.sources"
[[ "$(awk '/^URIs:/ { print $2 }' "$demo_sources")" == "$DIST_UPDATES_URL" ]] \
  || fail "the demo updates do not come from $DIST_UPDATES_URL"
grep -Fxq "Suites: $DIST_CODENAME-demo" "$demo_sources" || fail "the demo updates use the wrong suite"
grep -Fxq 'Signed-By: /usr/share/keyrings/lumo-archive-keyring.asc' "$demo_sources" \
  || fail "the demo updates are not signed by the archive key"
grep -Fxq 'apt/lumo-demo.sources usr/share/lumo/apt' "$package_root/debian/lumo-archive.install" \
  || fail "the demo updates are not kept out of APT until turned on"
channel="$package_root/channel/lumo-update-channel"
[[ -x "$channel" ]] || fail "lumo-update-channel is not executable"
sh -n "$channel" || fail "lumo-update-channel has a syntax error"
grep -Fq 'sources=/etc/apt/sources.list.d/lumo-demo.sources' "$channel" \
  || fail "lumo-update-channel does not manage the demo sources"
grep -Fq 'template=/usr/share/lumo/apt/lumo-demo.sources' "$channel" \
  || fail "lumo-update-channel does not use the shipped demo sources"
grep -Fq '<annotate key="org.freedesktop.policykit.exec.path">/usr/libexec/lumo-update-channel</annotate>' \
  "$package_root/channel/org.lumo.update-channel.policy" || fail "the update channel policy names the wrong program"
grep -Fq '<allow_active>auth_admin_keep</allow_active>' "$package_root/channel/org.lumo.update-channel.policy" \
  || fail "changing the update channel does not ask for an administrator"
grep -Fq 'install -m 0644 /usr/share/lumo/apt/lumo-demo.sources /etc/apt/sources.list.d/lumo-demo.sources' \
  "$package_root/debian/lumo-archive.postinst" || fail "updates do not refresh turned-on demo sources"
grep -Fq 'rm -f /etc/apt/sources.list.d/lumo-demo.sources' "$package_root/debian/lumo-archive.postrm" \
  || fail "purging does not remove the demo sources"
grep -Fq '"origin=Debian,codename=trixie-security,label=Debian-Security";' "$apt/51lumo-unattended-upgrades" \
  || fail "security updates are not installed automatically"
grep -Fxq 'APT::Periodic::Unattended-Upgrade "1";' "$apt/21lumo-auto-upgrades" \
  || fail "unattended upgrades are not enabled"
for timer in apt-daily apt-daily-upgrade; do
  grep -Fxq 'ConditionKernelCommandLine=!boot=live' "$package_root/systemd/$timer.timer.d/lumo-live.conf" \
    || fail "$timer runs in the live session"
done

printf 'lumo-archive source test: OK\n'
