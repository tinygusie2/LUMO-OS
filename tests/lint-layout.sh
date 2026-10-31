#!/usr/bin/env bash
set -Eeuo pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

required_paths=(
  archive/reprepro/conf/distributions.in
  configs/project.env
  configs/live/packages.txt
  configs/live/excluded-packages.txt
  configs/live/grub.cfg
  configs/live/live-user.env
  configs/live/sddm-autologin.conf.in
  configs/rootfs/minimal-packages.txt
  configs/upstream/base.env
  configs/upstream/debian.sources.in
  docs/ARCHITECTURE.md
  keys/debian-trixie-fingerprints.txt
  manifests/source-packages.txt
  manifests/derived-packages.txt
  manifests/native-packages.txt
  packages/native
  packages/derived
  packages/derived/base-files/debian/changelog
  packages/derived/base-files/etc/os-release
  packages/native/lumo-base/debian/control
  packages/native/lumo-base/debian/changelog
  packages/native/lumo-archive/debian/control
  packages/native/lumo-archive/debian/changelog
  packages/native/lumo-desktop/debian/control
  packages/native/lumo-desktop/debian/changelog
  packages/native/lumo-apps/debian/control
  packages/native/lumo-apps/debian/changelog
  packages/native/lumo-apps/CMakeLists.txt
  packages/native/lumo-desktop/data/ui/qmldir
  configs/live/lumo-live-language
  packages/native/lumo-desktop/data/calamares/settings.conf
  packages/native/lumo-desktop/data/wallpaper/org.lumo.tower/metadata.json
  packages/native/lumo-desktop/data/icons/lumo-logo.svg
  packages/native/lumo-desktop/data/symbols.lock
  packages/native/lumo-desktop/data/shell/m3/qmldir
  packages/native/lumo-desktop/data/shell/launcher/metadata.json
  packages/native/lumo-desktop/data/shell/shade/metadata.json
  packages/native/lumo-desktop/tools/lumo_design.py
  packages/native/lumo-desktop/tools/m3color.py
  docs/DESKTOP.md
  scripts/preview-desktop
  configs/live/apt-preferences
  configs/live/kscreenlockerrc
  configs/live/kwalletrc
  scripts/fetch-sources
  scripts/bootstrap-debian-signer-keyring
  scripts/bootstrap-build-tools
  scripts/bootstrap-iso-tools
  scripts/build-base-files-source
  scripts/create-build-rootfs
  scripts/build-base-files-binary
  scripts/build-lumo-base-source
  scripts/build-lumo-base-binary
  scripts/build-lumo-archive-source
  scripts/build-lumo-archive-binary
  scripts/create-archive-key
  scripts/publish-updates
  scripts/build-lumo-desktop-source
  scripts/build-lumo-desktop-binary
  scripts/create-development-archive-key
  scripts/build-local-archive
  scripts/build-minimal-rootfs
  scripts/build-live-rootfs
  scripts/build-iso
  scripts/smoke-test-iso
  scripts/unpack-sources
  tests/test-base-files-identity.sh
  tests/test-base-files-binary.sh
  tests/test-lumo-base-source.sh
  tests/test-lumo-base-binary.sh
  tests/test-lumo-archive-source.sh
  tests/test-lumo-archive-binary.sh
  tests/test-lumo-desktop-source.sh
  tests/test-lumo-desktop-binary.sh
  tests/test-local-archive.sh
  tests/test-minimal-rootfs.sh
  tests/test-live-rootfs.sh
  tests/test-iso.sh
)

for required_path in "${required_paths[@]}"; do
  [[ -e "$project_root/$required_path" ]] || {
    printf 'missing required path: %s\n' "$required_path" >&2
    exit 1
  }
done

if find "$project_root/keys" -type f \( -name '*.key' -o -name '*.sec' \) -print -quit \
  | grep -q .; then
  printf 'private-looking key material found under keys/\n' >&2
  exit 1
fi

leftovers=$(cd "$project_root" && grep -rIni 'kernora' . \
  --exclude-dir=.git --exclude-dir=_build --exclude-dir=_state --exclude-dir=out \
  --exclude=LICENSE --exclude=NOTICE --exclude=README.md --exclude=CLAUDE.md \
  --exclude=changelog --exclude=copyright --exclude=WIFI_REALTEK.md \
  --exclude=CLAUDE_STORE_HANDOFF.md --exclude=UPDATES.md --exclude=lint-layout.sh \
  | grep -Ev 'SPDX-FileCopyrightText: .*Kernora|^[^:]*\.patch:[0-9]+:Author: Kernora' \
  | grep -Ev '^\./configs/live/live-user\.env:[0-9]+:LIVE_USER_PASSWORD_HASH=' \
  | grep -Ev '^\./configs/live/grub\.cfg:[0-9]+:.*usr/share/kernora/settings/Main\.qml' \
  | grep -Ev '^\./tests/test-iso\.sh:[0-9]+:.*(usr/share/kernora/settings/Main\.qml|before the Lumo rename)' \
  | grep -Ev "^\./tests/test-(live-rootfs|lumo-archive-source)\.sh:[0-9]+:.*(grep -rq?i 'commywork9282-dotcom\\\\\|kernora'|upstream Kernora archive)" \
  || true)
if [[ -n "$leftovers" ]]; then
  printf 'internal names must say lumo, not kernora:\n%s\n' "$leftovers" >&2
  exit 1
fi

printf 'layout test: OK\n'
