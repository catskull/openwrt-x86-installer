# openwrt-x86-installer

Bootable ISO that installs OpenWrt on any x86 system. Based on Alpine Linux.
Bundles the latest stable OpenWrt image and can download any other release at runtime.

## Usage

### Build

Requires Docker.

```bash
make iso
# output: dist/openwrt-x86-installer.iso
```

### Write to USB

```bash
sudo dd if=dist/openwrt-x86-installer.iso of=/dev/sdX bs=4M status=progress && sync
```

### Install

Boot from the USB drive and follow the menu:

1. Select target disk
2. Select OpenWrt version (bundled or download)
3. Select image type (ext4 recommended)
4. Confirm — disk will be erased
5. Reboot

### Test in QEMU

```bash
qemu-img create -f qcow2 test-disk.qcow2 1G

qemu-system-x86_64 \
  -m 512m \
  -cdrom dist/openwrt-x86-installer.iso \
  -drive file=test-disk.qcow2,format=qcow2 \
  -boot d \
  -nic user,model=e1000

# Boot installed system
qemu-system-x86_64 \
  -m 256m \
  -drive file=test-disk.qcow2,format=qcow2 \
  -nic user,model=e1000,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80
```

## CI

GitHub Actions builds the ISO on every push to `main` and on a weekly schedule
(to pick up new OpenWrt releases). Tagged releases (`v*`) publish the ISO as a
GitHub Release artifact.

## TODO

- **Headless / SSH support** — enable the OpenSSH server in the live environment
  by default and verify the installer script works non-interactively (useful for
  scripted provisioning).

- **Test unbundled versions** — exercise the stable release list, RC, and snapshot
  download paths end-to-end. Verify checksum validation, progress display, and
  error handling when a download fails or the network is unavailable.

- **Updates** — think through how a user would upgrade an existing OpenWrt
  installation. Options: re-run the installer (destructive), sysupgrade from
  within OpenWrt, or a separate upgrade mode in the installer that uses
  `sysupgrade` instead of `dd`.

- **Smarter CI trigger** — instead of a fixed weekly schedule, trigger a build
  only when OpenWrt publishes a new stable release (e.g. poll the downloads page
  or watch an RSS/Atom feed via a lightweight GitHub Action).
