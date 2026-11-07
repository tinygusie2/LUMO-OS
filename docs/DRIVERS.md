# Drivers

AMD and Intel graphics work with the kernel's own drivers and the firmware the
image ships. The kernel, firmware and Mesa come from `trixie-backports`, so
recent cards such as AMD Radeon RX 9000 and Intel Arc B-series work too (see
`UPDATES.md`). NVIDIA cards need NVIDIA's driver. Lumo installs it by itself,
and only on computers that have an NVIDIA card.

## What gets installed

`/usr/libexec/lumo-drivers` (lumo-desktop) looks at `/sys/bus/pci/devices`
for an NVIDIA display controller (vendor `0x10de`, class `0x0300` or
`0x0302`). It takes the highest device ID it finds:

| PCI device ID | Cards | Driver |
| --- | --- | --- |
| `0x1e00` and up | GeForce GTX 16, RTX 20 and newer, RTX 50 included | `nvidia-open` from NVIDIA's Debian 13 repository |
| `0x1340` to `0x1dff` | GeForce GTX 900 and 10 | `nvidia-driver` from Debian `contrib non-free`, from `trixie-backports` when it is newer |
| below `0x1340` | older cards | none; they stay on nouveau |

Without an NVIDIA card the tool stops after reading sysfs: no sources are added
and nothing is downloaded.

NVIDIA's repository (`developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/`)
is added only when it is needed. Its key ships in lumo-desktop
(`/usr/share/lumo/nvidia-archive-keyring.gpg`, fingerprint
`0218 2E60 104F CDC2 6EAE 1B85 97A5 D4CB 8793 F200`). Debian 13 has no driver
for RTX 50 cards, and NVIDIA's repository no longer carries the 580 branch that
GTX 900 and 10 need. Hence the two sources.

`/etc/apt/preferences.d/lumo-nvidia.pref` pins NVIDIA's repository to 100,
and its NVIDIA packages (`*nvidia*`, `libcuda*` and the like) to 600. NVIDIA
also publishes `dkms`, for example, and that stays Debian's.

After `apt-get install`, the tool checks that DKMS built `nvidia.ko` for every
kernel with headers. It then writes
`/etc/modprobe.d/lumo-nvidia.conf` (`nvidia-drm modeset=1 fbdev=1`),
regenerates the initramfs and cleans the APT cache. If any step fails, the
driver is purged again and the computer keeps using nouveau.

## When it runs

- **Installer.** `shellprocess@drivers` runs `lumo-drivers install --target`
  in the new system after the update step, when the computer is online.
- **Installed system.** `lumo-drivers.timer` starts the check 90 seconds
  after it is activated: at boot, or right after lumo-desktop is installed.
  It repeats the check every six hours. The check installs the driver in the
  background; the update notifier says so, and asks for a restart when the
  driver is ready (`/run/lumo-driver-ready`).
- **Settings › System › Drivers.** Shows the card, the driver's state and
  version, and installs or removes the driver through `pkexec` (polkit action
  `org.lumo.drivers`, which starts `lumo-drivers@install` or
  `@remove`).

The automatic check skips:

- the live session;
- computers with Secure Boot on, because the key has to be confirmed at the
  next boot (see below); Settings installs the driver there;
- a driver the user removed in Settings;
- a failed attempt, for a day.

`automatic=false` in `/etc/lumo/drivers.conf` (the switch in Settings) turns
the automatic install off.

State lives in `/var/lib/lumo/drivers/state`: `installing`, `installed`,
`failed`, `offline`, `secureboot`, `removing` or `removed`, plus the device,
its name from `pci.ids` and the time.

## Firmware and the initramfs

`lumo-desktop` installs the initramfs hook
`/usr/share/initramfs-tools/hooks/zz-lumo-firmware`, which runs after the
standard hooks and removes nouveau's firmware (`usr/lib/firmware/nvidia/<chip>`)
from the initramfs; the versioned folders of NVIDIA's own driver stay. The
kms hook only queues nouveau, and mkinitramfs copies queued modules and their
firmware after all hooks, so the hook first runs `apply_add_modules` itself. With
the trixie-backports kernel and `MODULES=most`, the kms hook otherwise copies
every GPU firmware file in, NVIDIA's GSP blobs alone taking 152 MB: the live
initramfs was 223 MB compressed and 379 MB unpacked, and a machine with 1 GB
of memory stopped with "Initramfs unpacking failed" and "No working init
found". Nouveau and NVIDIA's driver load their firmware from the root file
system after it is mounted; AMD and Intel firmware stays in the initramfs so
their early KMS and the boot splash keep working. `tests/test-live-rootfs.sh`
fails when nouveau's firmware reappears or the initramfs reaches 160 MB.
## The Drivers app

`lumo-drivers` (the app, `/usr/bin`) has three pages: Drivers, Devices and
Updates. Settings › System › Drivers opens it. It needs three tools from
`lumo-desktop`:

* `/usr/libexec/lumo-hardware` runs as the user and prints JSON: every PCI
  and USB device with its name, driver, module and status, the CPU, the
  computer, what the catalog offers here and the NVIDIA status. `report` prints
  the same as text without serial numbers, MAC addresses or the host name, so
  people can paste it in a chat.
* `/usr/share/lumo/hardware/catalog.json` lists what can be installed. Only
  ids from this file can be requested, so a request can never name an
  arbitrary package.
* `/usr/libexec/lumo-driver-job` does the root work. `lumo-drivers request
  add|drop|flash NAME` runs through the same polkit action as before, writes
  `/run/lumo-drivers/job.json` and starts `lumo-driver-job.service`, so
  closing the app does not stop the job. The app reads the JSON for progress.

Nothing here installs by itself. Only the NVIDIA driver is automatic, as above.

| Item | Offered when | Notes |
| --- | --- | --- |
| Broadcom Wi-Fi | a listed `14e4` card has no working Wi-Fi | Needs `non-free`, DKMS, a restart, and Secure Boot off |
| Firmware for a device | the kernel failed to load a file and the package isn't installed | From the `firmware` table in the catalog |
| Printers and scanners | always, recommended with a USB printer | Open goes to the Plasma printer settings |
| Firmware updates | on real hardware | `fwupd`, then the Updates page lists LVFS releases |
| Virtual machine tools | QEMU/KVM, VMware or Hyper-V | Recommended there |
| Intel video encoding | Intel graphics | Needs `non-free`, replaces `intel-media-va-driver` |
| Graphics card computing | Intel or AMD graphics | `mesa-opencl-icd` |

Safety rules of the job: it simulates first and stops if apt wants to remove
anything the catalog doesn't name in `replaces`. If the install fails it purges
what it added, restores what it replaced and takes the source back. Removing
only touches packages the job installed (`/var/lib/lumo/drivers/items/`),
keeps packages another item or the NVIDIA driver still uses, and stops if a
manually installed package would go with them. The `non-free` source stays
while a tracked item or the legacy NVIDIA driver needs it.

`groups` in the catalog are for tools that check a Unix group. CUPS only lets
members of `lpadmin` add printers and otherwise asks for a root password, which
a Lumo user doesn't have. So the job adds everyone in `sudo` when the item is
installed and again on each scan, for accounts made later. cupsd reads the
group itself, so it works right away without logging out.

Missing firmware comes from `lumo-driver-job scan`, which reads the kernel
log as root (`Direct firmware load for X failed with error -2`) on the driver
timer and after each job, and writes
`/var/lib/lumo/drivers/firmware-missing.json`. A file is ignored when a file
with the same stem exists, because drivers ask for the newest version first and
fall back.

Driver updates are the normal PackageKit updates, filtered with the `updates`
patterns in the catalog, and `Updates.install(names)` installs just those.

## Secure Boot

With Secure Boot on, the kernel loads only signed modules. Lumo signs the
NVIDIA module with its own key, so Secure Boot can stay on. That matters for
games whose anti-cheat requires it, such as Fortnite with Easy Anti-Cheat
Linux v2.

- Before the driver is installed, `lumo-drivers` makes the key DKMS signs
  with: `/var/lib/dkms/mok.key` (root only) and `/var/lib/dkms/mok.pub`
  (DER), an RSA 2048 certificate called "Lumo driver signing key". DKMS signs
  every module it builds with it, also after kernel updates. The installer
  makes the key too, so modules built there are signed.
- After DKMS built the module, `mokutil --import` queues the key with a
  one-time eight-digit password, kept in `/var/lib/lumo/drivers/enroll`.
  The installer does not queue it, because nobody would see the password;
  Settings then shows "Set up Secure Boot".
- `lumo-drivers status` reports `mok=none|enrolled|pending|missing` and,
  while the key is pending, `mokpassword=`. Settings shows the password and
  the steps: at the next boot MokManager appears; choose Enroll MOK,
  Continue, Yes, type the password and choose Reboot.
- Once `mokutil --test-key` reports the key as enrolled, the boot check
  deletes the password file. Removing the driver withdraws a key that is
  still pending.

## Testing without the hardware

QEMU has no NVIDIA card, so a test VM shows the tool a fake device:

```sh
mkdir -p /tmp/fakepci/0000:01:00.0
echo 0x10de > /tmp/fakepci/0000:01:00.0/vendor
echo 0x2f04 > /tmp/fakepci/0000:01:00.0/device
echo 0x030000 > /tmp/fakepci/0000:01:00.0/class
mount --bind /tmp/fakepci /sys/bus/pci/devices
```

The driver installs and DKMS builds the module. The system still boots
normally, because without the card the module never loads.

The same trick works for the catalog, for example vendor `0x14e4`, device
`0x43b1`, class `0x028000` offers Broadcom Wi-Fi. `tests/test-lumo-desktop-source.sh`
runs the scanner over a fake `/sys` with `lumo-hardware --root DIR`.

## VLC on NVIDIA

VLC 3 draws video through XWayland, and with the NVIDIA driver its hardware
decoding (VDPAU/VA-API) shows green bars along the bottom of videos. So on
PCs where the `nvidia` module is loaded, the session script
`/etc/xdg/plasma-workspace/env/lumo-video-decoding.sh` adds
`avcodec-hw=none` to VLC's config once, for the Debian VLC
(`~/.config/vlc/vlcrc`) and the Flathub one
(`~/.var/app/org.videolan.VLC/config/vlc/vlcrc`). If you already picked a
decoder yourself it's left alone, and a marker in
`~/.local/state/lumo/vlc-decoding/` makes sure it never overrides a later
change in VLC's preferences. Without an NVIDIA driver nothing happens.
