# Lumo

Lumo is a desktop Linux distribution for people coming from Windows. It is
based on Debian 13 (trixie) and runs KDE Plasma 6 with its own shell, apps and
themes, designed after Material 3.

Lumo is a fork of [Kernora OS](https://github.com/commywork9282-dotcom/Kernora-OS-)
by the Kernora Developers, under the same licence. Since lumo-desktop 1.4.57
the packages, files, themes and code use the Lumo name as well. See `NOTICE`
for the credits.

This repository has everything needed to build the live ISO: Lumo's own
packages, the changes made to a few Debian packages, the image configuration,
and the build scripts and tests.

The project is in early development. Packages are signed with a development
key for now; there is no release key yet.

If an older image leaves an installed system at a black screen, see
[boot recovery](docs/BOOT-RECOVERY.md).

## What's in the image

- Debian 13.6 from a fixed snapshot (2026-09-01), Linux 6.12, KDE Plasma 6.3.
- A Lumo shell on top of Plasma: panel, app launcher, quick settings with an
  agenda under the clock, notifications, lock screen, Alt+Tab and power menu.
  All colours come from one seed colour, `#ff6a1e`. Settings can switch the
  look between Material Design 1, 2 and 3. Google Sans Flex is the typeface.
- Lumo apps in place of KDE's: Settings, Files, Text Editor, Photos, Media
  Player, Calculator, Screenshot, Task Manager, Calendar, Store, Terminal
  (Alacritty) and Welcome, plus a file chooser that every program uses.
- For people coming from Windows:
  - Windows shortcuts: Meta+E, Meta+I, Meta+R, Meta+Shift+S, Ctrl+Shift+Esc,
    Meta+Tab, Meta+Up/Down and more ([list](docs/DESKTOP.md#shortcuts));
  - Settings > System > Bring files from Windows copies documents, pictures,
    the wallpaper and browser bookmarks from a Windows drive or USB stick;
  - Wine opens `.exe` files; GameMode and MangoHud are installed, and Steam,
    Bottles, Lutris and Heroic are one click away in the Store;
  - Gaming Mode and Power Mode in quick settings;
  - Phone (KDE Connect): phone notifications, texts, files, the clipboard and
    Find my phone;
  - Printers & scanners that work without drivers;
  - a PIN for the lock screen.
- A Bluetooth pairing agent that shows and asks for pairing codes.
- Live wallpapers: Lumo Shapes, Tower, Rhythm, Starfall and Pastel.
- LibreWolf as the browser, from the LibreWolf repository.
- Calamares as the installer, restyled to match.
- English, Dutch and Russian. The live session language is chosen in the boot
  menu.
- Updates: Debian security updates, the kernel's among them, and LibreWolf
  updates install by themselves once a day. Debian point releases and Lumo's
  own packages are offered in Settings > Updates. Lumo never restarts by
  itself. See [docs/UPDATES.md](docs/UPDATES.md).

KDE's standalone apps (Dolphin, Konsole, Kate, Discover, Spectacle and others)
are left out; the list is in `configs/live/excluded-packages.txt`.

## Installing

Install Lumo on an SSD. A hard disk (HDD) is not recommended: apps, menus and
the first minute after login are very slow on one, because the desktop reads
many small files at once. The installer asks for at least 12 GB of disk space
and 1.5 GB of RAM.

## Building

You need a Debian-based machine (Debian 13 in WSL 2 works) with:

- unprivileged user namespaces and subuid/subgid mappings (everything builds
  without root);
- `apt-get`, `dpkg-dev`, `curl`, `gpg`, `gpgv`, `mmdebstrap` and `uidmap`;
- `grub-common`, `grub-pc-bin`, `grub-efi-amd64-bin`, `xorriso`,
  `squashfs-tools` 4.7 or newer and `xz-utils` for the ISO;
- `libxml2-utils`, `libarchive-tools`, `file`, `mtools`, `gettext`,
  `reprepro`, `librsvg2-bin` and `shellcheck` for the checks;
- `qemu-system-x86` and `ovmf` for the boot tests;
- about 15 GB of free disk space.

Debian 13 ships `squashfs-tools` 4.6.1, which lacks `-numeric-owner`. Take
4.7 from Debian forky: unpack its `.deb` with `dpkg-deb -x` and put
`mksquashfs` and `unsquashfs` first in `PATH`.

The host's own APT setup is not touched. Keyrings, tools and caches live in
the working tree.

Fetch the sources, then build the ISO and check that it boots in QEMU (BIOS
and UEFI):

```sh
make sources
make iso-smoke
```

The result is `out/iso/lumo-1-ember-live-amd64.iso` with a `.sha256`
file next to it. `make iso` builds the ISO without the boot tests.

Steps can also be run one at a time, for example `make local-archive` (all
packages and the signed APT archive) or `make live-rootfs`. See the
`Makefile` for the full list.

The live root file system is built in `/var/tmp`, because `/tmp` is often a
small tmpfs; set `LUMO_TMPDIR` to use another place. The ISO build stages
its squashfs in `_build/`; set `LUMO_SCRATCH_DIR` to stage it elsewhere.

Builds are reproducible: the Debian snapshot, tool versions and every
downloaded file are pinned by SHA-256, and archives are written with fixed
file order, times and owners. Build outputs (`_build/`, `_cache/`, `out/`,
`_state/`) stay out of Git.

To try changes to the shell or the apps without rebuilding the ISO,
`scripts/preview-desktop` boots the desktop in QEMU and syncs files into it.

## Layout

- `packages/native/`: Lumo's own packages (`lumo-base`,
  `lumo-archive`, `lumo-desktop`, `lumo-apps`).
- `packages/derived/`: changes to Debian's `base-files`, Calamares and
  `polkit-kde-agent-1`.
- `configs/`: the upstream pins, the live image and the system identity.
- `scripts/`: build steps. `tests/`: checks for every package and image.
- `docs/`: how it all works. Start with
  [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), then
  [docs/DESKTOP.md](docs/DESKTOP.md) for the shell and design system,
  [docs/APPS.md](docs/APPS.md) for the apps,
  [docs/UPDATES.md](docs/UPDATES.md) for updates and publishing them, and
  [docs/DRIVERS.md](docs/DRIVERS.md) for the graphics drivers Lumo installs
  by itself.

## License

Lumo is released under the GNU GPL version 3 (`LICENSE`), like Kernora OS.
Its own files are GPL-2.0-or-later. `NOTICE` lists the parts that come from
others and their licences, among them Google Sans Flex (SIL OFL 1.1).
