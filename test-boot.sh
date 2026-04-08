#!/usr/bin/env bash
# Boot the installed OpenWrt system from the test disk.
# SSH:  ssh -p 2222 root@localhost
# Web:  http://localhost:8080  (only works if LuCI binds to all interfaces)
set -euo pipefail

DISK="test-disk.qcow2"

if [[ ! -f "$DISK" ]]; then
    echo "ERROR: $DISK not found. Run test-install.sh first." >&2
    exit 1
fi

qemu-system-x86_64 \
    -m 256m \
    -drive file="$DISK",format=qcow2 \
    -nic user,model=e1000,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80
