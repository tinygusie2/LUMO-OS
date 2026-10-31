# Updates

An installed Lumo system updates from three APT archives. The
`lumo-archive` package sets them up, and `lumo-base` depends on it, so
every installation has it.

| Archive | What comes from it | How it is installed |
| --- | --- | --- |
| Debian security, `security.debian.org`, `trixie-security` | security fixes, kernel updates among them | automatically, once a day |
| LibreWolf, `repo.librewolf.net` | the browser | automatically, once a day |
| Debian, `deb.debian.org`, `trixie` and `trixie-updates` | Debian point releases | in Settings > Updates |

Lumo has no update archive of its own yet. Until lumo-archive 1.4 the system
also updated from the upstream Kernora archive
(`commywork9282-dotcom.github.io/kernora-updates`, priority 900), whose
packages could replace Lumo's. That source is gone; Lumo's own packages change
only with a new image until Lumo publishes its own archive (see below).

The ISO is still built from the pinned Debian snapshot (`configs/upstream/base.env`).
Only the installed system points at the live archives: `build-live-rootfs` removes
the build's `sources.list` and its copy of the Lumo archive.

Both the Debian archive and its security updates come with the `main` and
`non-free-firmware` components. The image ships the firmware that graphics
cards, Wi-Fi, Bluetooth and laptop sound need, and CPU microcode
(`configs/live/packages.txt`: AMD, Intel and NVIDIA graphics, Intel, Realtek,
Qualcomm, MediaTek and Broadcom Wi-Fi, SOF sound); without it AMD's integrated
graphics stop with "Fatal error during GPU init" and most Wi-Fi stays dark.

The installer copies the system on the medium, which may be days of updates
behind. When the computer is online it brings the new system up to date before
it finishes (`shellprocess@upgrade` in `data/calamares/settings.conf`:
`apt-get update`, `full-upgrade` and `update-grub` in the target). Offline,
the step is skipped and Settings > Updates catches up later.

## Automatic updates

`unattended-upgrades` runs from APT's daily timers. `lumo-archive` enables it
in `/etc/apt/apt.conf.d/21lumo-auto-upgrades` and chooses what it installs in
`51lumo-unattended-upgrades`. Debian's own defaults match archives by the
distribution's codename. On Lumo that codename is `ember`, so they would match
nothing; the Lumo file names `trixie-security` instead.

A kernel update takes effect after a restart. The live session never updates
itself: the timers carry `ConditionKernelCommandLine=!boot=live`.

Settings > Updates shows everything else through PackageKit and installs it on
request.

## Notifications

`lumo-update-notifier` (lumo-apps) starts with the session from
`/etc/xdg/autostart/org.lumo.update-notifier.desktop`. Two minutes after
login, and then every six hours, it asks PackageKit for updates. It refreshes
the package lists itself only when APT's daily refresh is more than a day old
and the connection is not metered. When the list holds a package it has not
announced yet, a notification from Settings says how many updates are ready,
and whether security fixes are among them; "View" opens Settings > Updates.
When `/run/reboot-required` appears (the kernel hook of `unattended-upgrades`
creates it), it asks once per boot for a restart, with a "Restart" button that
opens the session's restart prompt.

The events are in `lumo-updates.notifyrc`, so the notification server draws
them like any other Lumo notification. What has been announced is kept in
`~/.local/state/lumo-update-notifierstaterc`. The notifier exits at once in
the live session.

## What's new

After an update, the next login opens a "What's new" window: Welcome started
as `lumo-welcome --whats-new`. It says what changed, in plain words, from
the release notes in `/usr/share/lumo/whatsnew.json`
(`packages/native/lumo-apps/data/whatsnew.json`). Each release there has an
`id` (its date, newest first; a second release on the same day gets a suffix
such as `2026-10-08-2`) and items with an icon, a title and a text, each in
English and Russian. Releases of the same day are shown as one.

The notifier opens the window when the newest `id` differs from `Seen` in
`lumo-welcomerc` `[WhatsNew]`, six seconds after login. On a new
installation, where Welcome itself is still due, it only records the newest
release as seen. The window shows every release since the one seen last (up
to three when none was seen yet) and then records the newest.

## Debian does not replace Lumo's builds

Lumo builds its own versions of `base-files`, Calamares and
`polkit-kde-agent-1`. `/etc/apt/preferences.d/lumo-archive.pref` pins every
version of those packages whose version contains `lumo` at priority 1000, so a
newer Debian version of the same package is never installed over it. Without
the pin a Debian point release would replace `base-files` and the system would
call itself Debian.

## Publishing updates later

The scripts for an archive of Lumo's own are in place, but nothing is
published yet:

1. `scripts/create-archive-key` creates the Lumo Archive Signing Key in
   `_state/gnupg/archive`, writes the public key to
   `packages/native/lumo-archive/keyrings/lumo-archive-keyring.asc`, sets
   `DIST_ARCHIVE_KEY_FINGERPRINT` in `configs/project.env` and makes one
   backup, `~/lumo-archive-key-secret.asc`. Keep that backup offline.
2. Create the `tinygusie2/lumo-updates` repository with GitHub Pages
   (`DIST_UPDATES_URL` and `DIST_UPDATES_REPOSITORY` in `configs/project.env`).
3. Add `apt/lumo.sources` (pointing at `DIST_UPDATES_URL`, signed by the key)
   and the keyring back to `lumo-archive`, and its tests.
4. `make publish` builds every package and the local archive, signs it and
   force-pushes it to `lumo-updates`.

## Systems installed before the rename

Systems installed from an image with the `kernora-*` packages cannot move to
the `lumo-*` packages through an update, because no archive offers them.
Install them again from a new image. The boot menu of a new image still finds
and starts such an installation (`configs/live/grub.cfg` looks for both
`/usr/share/lumo` and `/usr/share/kernora`).
