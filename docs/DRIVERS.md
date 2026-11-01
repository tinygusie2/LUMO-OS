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
- computers with Secure Boot on (the DKMS module would not load until its key
  is enrolled);
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
