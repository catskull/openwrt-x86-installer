#!/usr/bin/env bash
# Boot the installer ISO in QEMU against a fresh test disk.
set -euo pipefail

ISO="dist/openwrt-x86-installer.iso"
DISK="test-disk.qcow2"

if [[ ! -f "$ISO" ]]; then
    echo "ERROR: $ISO not found. Run 'make iso' first." >&2
    exit 1
fi

if [[ ! -f "$DISK" ]]; then
    echo "Creating $DISK..."
    qemu-img create -f qcow2 "$DISK" 1G
fi

qemu-system-x86_64 \
    -m 512m \
    -cdrom "$ISO" \
    -drive file="$DISK",format=qcow2 \
    -boot d \
    -nic user,model=virtio
