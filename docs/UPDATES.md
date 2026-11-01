# Updates

An installed Lumo system updates from five APT archives, six with demo
updates on. The `lumo-archive` package sets them up, and `lumo-base`
depends on it, so every installation has it.

| Archive | What comes from it | How it is installed |
| --- | --- | --- |
| Debian security, `security.debian.org`, `trixie-security` | security fixes, kernel updates among them | automatically, once a day |
| LibreWolf, `repo.librewolf.net` | the browser | automatically, once a day |
| Debian, `deb.debian.org`, `trixie` and `trixie-updates` | Debian point releases | in Settings > Updates |
| Debian backports, `deb.debian.org`, `trixie-backports` | the kernel, graphics firmware and Mesa | automatically, once a day |
| Lumo, `tinygusie2.github.io/lumo-updates` | Lumo's own packages | in Settings > Updates |
| Lumo demo, same site, `ember-demo` | new Lumo packages before everyone else, only with Demo updates on | in Settings > Updates, after turning it on in Settings > System |

Until lumo-archive 1.4 the system updated from the upstream Kernora archive
(`commywork9282-dotcom.github.io/kernora-updates`, priority 900), whose
packages could replace Lumo's. lumo-archive 1.4 dropped it, and 1.5 points at
Lumo's own archive instead.

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

## Kernel and graphics from backports

Debian 13's kernel (6.12) and Mesa are too old for recent graphics cards,
such as AMD Radeon RX 9000 and Intel Arc B-series. Lumo takes these from
`trixie-backports` instead. Backports are off by default in APT (priority
100); `lumo-backports.pref` (lumo-archive) raises only these source
packages to 500, so the newer version wins:

- `linux`, `linux-signed-amd64`: the kernel, signed for Secure Boot;
- `linux-base`: the kernel's install hooks, which the backports kernel needs in a newer version;
- `firmware-nonfree`, `firmware-free`: firmware for new GPUs and Wi-Fi;
- `mesa`, `libdrm`: OpenGL, Vulkan and video decoding;
- `nvidia-graphics-drivers`, `nvidia-graphics-drivers-tesla`: Debian's
  NVIDIA driver for GTX 900 and 10, so its DKMS module keeps building
  against the newer kernel (see `DRIVERS.md`).

Every other package stays on Debian 13. The ISO build uses the same file,
with `trixie-backports` from the pinned snapshot, and
`tests/test-live-rootfs.sh` checks that the kernel and Mesa in the image
carry a `~bpo13+` version. Backports updates install automatically like
security updates (`51lumo-unattended-upgrades`), because the kernel's
security fixes arrive there.

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
`~/.local/state/lumo-update-notifierstaterc`. In the live session the
notifier only keeps the app icons in shape (docs/DESKTOP.md, Other apps'
icons) and checks no updates.

## Demo updates

Settings > System has a Demo updates switch under Early access, off by
default. Turning it on runs `/usr/libexec/lumo-update-channel set demo`
through pkexec (polkit action `org.lumo.update-channel`, admin password).
That copies
`/usr/share/lumo/apt/lumo-demo.sources` to
`/etc/apt/sources.list.d/lumo-demo.sources`, which adds the `ember-demo`
suite from the same site and key, and Settings checks for updates again.

Both suites come from the same site, so the 900 pin below covers both and APT
just takes the higher version. `ember-demo` only holds packages newer than the
normal ones, so a demo system gets those from it and everything else from
`ember`.

Turning it off removes the file. Demo versions that are already installed
stay, APT doesn't downgrade. As soon as the normal updates have the same or a
higher version the system is back in line with everyone else. When the
switch is on, `lumo-archive` refreshes the file on upgrade, and it removes
it on purge.

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

## Lumo's packages win

`/etc/apt/preferences.d/lumo-archive.pref` gives the Lumo archive
(origin `tinygusie2.github.io`) priority 900, so Lumo's packages win over
Debian's.

## Publishing an update

1. Change the package and add a changelog entry with a higher version.
2. If people will notice the change, add a release at the top of
   `packages/native/lumo-apps/data/whatsnew.json`.
3. If the ISO should carry the new version, update the pins in
   `configs/live/packages.txt` and the version checks in `tests/`.
4. Run `make publish` on the machine that holds the key. It builds every package and the local archive, runs
   `tests/test-publish-updates.sh`, then signs the archive with the Lumo
   archive key and force-pushes it to the `tinygusie2/lumo-updates` repository, which
   GitHub Pages serves a minute later. The demo suite there is kept, only the
   demo packages the new normal ones caught up with are dropped.

Systems pick it up at their next check: the daily refresh, or Check in
Settings > Updates.

`lumo-updates` holds only the current packages, normal and demo. Each
publication replaces all of its contents in a single commit, so the
repository does not grow.

### Demo first

`make publish-demo` builds the same way but leaves the normal updates exactly
as they are published. Into `ember-demo` it puts every package from
`out/archive` whose version is newer than the published normal one, replacing
what the demo had before, and it refuses when nothing is newer.

Give the packages the version the release will have. When the demo is good,
`make publish` the same tree: the packages are identical, systems on the demo
already have them and nothing reinstalls. If a package changes after it went
to the demo, raise its version again. Both commands refuse to publish a
package under a version the demo already has with other contents, because
systems that installed the demo would never get the change. They also warn
when a package changed but kept the version it is published with.

## The signing key

The Lumo Archive Signing Key has fingerprint
`DF06 884E A586 3BEE 786D BD71 34C2 11B6 09EA CEE3`, created 2026-11-01 with
`scripts/create-archive-key`; it expires after three years.

- The private key lives in `_state/gnupg/archive` on the owner's build
  machine and is never committed. Its one backup,
  `~/lumo-archive-key-secret.asc`, belongs offline. Without it no update can
  be published.
- The public key is
  `packages/native/lumo-archive/keyrings/lumo-archive-keyring.asc`, installed
  as `/usr/share/keyrings/lumo-archive-keyring.asc` and served next to the
  archive.
- Before it expires, extend it with `gpg --homedir _state/gnupg/archive
  --quick-set-expire <fingerprint> 3y`, run `scripts/create-archive-key`
  again to export it, and publish a new `lumo-archive`.

## Systems installed before the rename

Systems installed from an image with the `kernora-*` packages cannot move to
the `lumo-*` packages through an update, because no archive offers them.
Install them again from a new image. The boot menu of a new image still finds
and starts such an installation (`configs/live/grub.cfg` looks for both
`/usr/share/lumo` and `/usr/share/kernora`).
