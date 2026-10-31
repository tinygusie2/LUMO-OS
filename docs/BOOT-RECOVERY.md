# Black screen after installation from an older ISO

Affected images assigned UID/GID 1000 to the SquashFS root directory.
Calamares copied that owner to the installed `/`. systemd-tmpfiles rejected
unsafe path transitions from `/` to root-owned `/run`, so the login screen
could not finish starting. The kernel and system itself were still running.

New images explicitly set the SquashFS root to root:root, mode 0755, without
changing account ownership. lumo-calamares 1.4.6 also repairs the target
root during installation. lumo-base 1.2 repairs `/` when installed or
upgraded; restart afterwards to recreate the runtime directories.

QEMU guests with QXL could also hang when Xorg took over Plymouth's display.
lumo-desktop 1.4.6 stops retaining the splash and orders SDDM after
plymouth-quit. This fix was verified with a cold BIOS/GRUB boot of a copy of
the affected installed disk, using QXL and the normal quiet/splash options.

If an existing installation cannot reach Settings to install the update,
boot the Live session and repair its root directory from a terminal:

```sh
lsblk -f
# Replace /dev/sda1 with the installed system's root partition from lsblk.
sudo mkdir -p /mnt/lumo-repair
sudo mount /dev/sda1 /mnt/lumo-repair
# Verify that this is the installed Lumo system before changing its owner.
cat /mnt/lumo-repair/etc/os-release
sudo chown 0:0 /mnt/lumo-repair
sudo chmod 0755 /mnt/lumo-repair
# Also repair the splash handover before the installed login screen starts.
sudo sed -i 's/ --retain-splash//' /mnt/lumo-repair/usr/lib/systemd/system/plymouth-quit.service.d/plymouth-quit-lumo.conf
sudo mkdir -p /mnt/lumo-repair/etc/systemd/system/sddm.service.d
printf '[Unit]\nAfter=plymouth-quit.service\n' | sudo tee /mnt/lumo-repair/etc/systemd/system/sddm.service.d/plymouth.conf
sudo umount /mnt/lumo-repair
sudo reboot
```

These commands change only the root directory inode. Do not use recursive
chown: home directories must continue to belong to their users.

The regression test `tests/test-squashfs-root.sh` checks the tar-to-SquashFS
conversion as an unprivileged builder, and `tests/test-iso.sh` checks the
root inode in every built image in addition to the live account ownership.
