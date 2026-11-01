SHELL := /bin/bash

.PHONY: check keyring index signer-keyring sources unpack verify \
	build-tools build-rootfs base-files-source base-files-binary \
	lumo-base-source lumo-base-binary lumo-archive-source \
	lumo-archive-binary lumo-desktop-source \
	lumo-desktop-binary lumo-apps-source lumo-apps-binary \
	calamares-source calamares-binary \
	polkit-kde-agent-1-source polkit-kde-agent-1-binary \
	development-archive-key archive-key local-archive publish \
	minimal-rootfs iso-tools librewolf rquickshare live-rootfs iso iso-smoke

check:
	./scripts/check-host

keyring: check
	./scripts/bootstrap-debian-keyring

index: keyring
	./scripts/update-upstream-index

signer-keyring: index
	./scripts/bootstrap-debian-signer-keyring

sources: signer-keyring
	./scripts/fetch-sources
	./scripts/unpack-sources

unpack:
	./scripts/unpack-sources

verify:
	./tests/lint-layout.sh
	./tests/test-squashfs-root.sh
	./tests/test-base-files-identity.sh
	./tests/test-lumo-base-source.sh
	./tests/test-lumo-archive-source.sh
	./tests/test-lumo-desktop-source.sh
	./scripts/verify-sources

base-files-source: verify
	./scripts/build-base-files-source

build-tools: signer-keyring
	./scripts/bootstrap-build-tools

build-rootfs: build-tools
	./scripts/create-build-rootfs

base-files-binary: verify build-rootfs
	./scripts/build-base-files-binary

lumo-base-source: verify
	./scripts/build-lumo-base-source

lumo-base-binary: verify build-rootfs
	./scripts/build-lumo-base-binary

lumo-archive-source: verify
	./scripts/build-lumo-archive-source

lumo-archive-binary: verify build-rootfs
	./scripts/build-lumo-archive-binary

lumo-desktop-source: verify
	./scripts/build-lumo-desktop-source

lumo-desktop-binary: verify build-rootfs
	./scripts/build-lumo-desktop-binary

lumo-apps-source: verify
	./scripts/build-lumo-apps-source

lumo-apps-binary: verify build-rootfs
	./scripts/build-lumo-apps-binary

calamares-source: verify
	./scripts/build-calamares-source

calamares-binary: verify build-rootfs
	./scripts/build-calamares-binary

polkit-kde-agent-1-source: verify
	./scripts/build-derived-source polkit-kde-agent-1

polkit-kde-agent-1-binary: verify build-rootfs
	./scripts/build-derived-binary polkit-kde-agent-1

development-archive-key:
	./scripts/create-development-archive-key

local-archive: base-files-binary lumo-base-binary lumo-archive-binary lumo-desktop-binary \
		lumo-apps-binary calamares-binary polkit-kde-agent-1-binary \
		development-archive-key rquickshare
	./scripts/build-local-archive

minimal-rootfs: local-archive
	./scripts/build-minimal-rootfs

iso-tools: signer-keyring
	./scripts/bootstrap-iso-tools

librewolf:
	./scripts/fetch-librewolf

rquickshare:
	./scripts/fetch-rquickshare

archive-key:
	./scripts/create-archive-key

publish: local-archive
	./scripts/publish-updates

live-rootfs: local-archive librewolf
	./scripts/build-live-rootfs

iso: live-rootfs iso-tools
	./scripts/build-iso

iso-smoke: iso
	./scripts/smoke-test-iso
