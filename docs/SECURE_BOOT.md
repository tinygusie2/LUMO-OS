# Secure Boot

Lumo starts with Secure Boot on, through Debian's signed boot chain:
`shimx64.efi` (signed by Microsoft's third-party UEFI CA), then GRUB and the
kernel (both signed with Debian's key). Lumo signs nothing itself.

This is also the first step towards Easy Anti-Cheat Linux v2 (Fortnite and
other Epic games), which requires Secure Boot with well-known keys, a signed
kernel and signed modules. Debian's Secure Boot CA is on Epic's list.

## The ISO

`scripts/build-iso` builds the image with `xorriso` itself, not with
`grub-mkrescue`, whose EFI image is an unsigned GRUB:

- BIOS: `grub-mkimage -O i386-pc-eltorito` with the host's `i386-pc` modules,
  plus GRUB's hybrid MBR, as before.
- UEFI: `efi.img`, a FAT image with `EFI/BOOT/BOOTX64.EFI` (shim),
  `grubx64.efi` (Debian's signed `gcdx64.efi`) and `mmx64.efi` (MokManager).
  It is the El Torito UEFI image and GPT partition 2, so DVDs and USB sticks
  written with `dd` both boot. The same files sit in `/EFI/BOOT` in the ISO
  file system for tools that copy files to a FAT stick, as Rufus can.
- The signed files and `x86_64-efi` modules come from the live rootfs
  (`shim-signed`, `grub-efi-amd64-signed`, `grub-efi-amd64-bin`), so they
  match the snapshot.

`gcdx64.efi` finds the medium by `/.disk/info` and reads `/boot/grub/grub.cfg`.
With Secure Boot on, GRUB loads no modules from disk; Debian's signed image
has no `png` reader, so the menu shows without the theme's images. With
Secure Boot off, GRUB loads `png` from `/boot/grub/x86_64-efi`.

## The installed system

Calamares runs `grub-install`, which on Debian installs shim and the signed
GRUB to `EFI/lumo` when `grub-efi-amd64-signed` and `shim-signed` are present,
and points the firmware's boot entry at shim. Calamares' own fallback copy
(`installEFIFallback`) is off, because it copies `grubx64.efi` alone to
`EFI/BOOT/BOOTX64.EFI`, which does not start with Secure Boot on.
`shellprocess@efifallback` runs `grub-install --removable --no-nvram`
instead, which puts shim at `EFI/BOOT/BOOTX64.EFI`, and sets the debconf
question `grub2/force_efi_extra_removable` so that later `shim-signed`
upgrades refresh that copy too.

## Not done yet

- The NVIDIA driver for GTX 900 and 10 is built by DKMS and not signed;
  Lumo skips it with Secure Boot on (`DRIVERS.md`).
- Installations made before lumo-desktop 1.4.63 do not have shim. They keep
  starting with Secure Boot off.
- The other Easy Anti-Cheat Linux v2 requirements (IOMMU, `lockdown=integrity`,
  kexec off, BPF LSM) are not on the kernel command line.
