#!/usr/bin/env bash
# build-iso.sh
#
# Runs inside the Docker build container.
# 1. Patches the installer script with the bundled OpenWrt version string.
# 2. Calls Alpine's mkimage.sh to produce the base ISO.
# 3. Injects the bundled OpenWrt image into the ISO root so the installer
#    can find it at /media/usb/openwrt-bundled.img.gz after boot.

set -euo pipefail

APORTS_SCRIPTS="/aports/scripts"
BUILD_DIR="/build"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
ALPINE_VERSION="v3.21"
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine"

main() {
    # --- Resolve bundled OpenWrt version ---
    local openwrt_version="unknown"
    if [[ -f "${BUILD_DIR}/openwrt-image/version.txt" ]]; then
        openwrt_version=$(cat "${BUILD_DIR}/openwrt-image/version.txt")
    else
        echo "WARNING: No bundled OpenWrt image found (run fetch-openwrt.sh)."
        echo "         The ISO will be download-only."
    fi
    echo "Bundled OpenWrt version: $openwrt_version"

    # --- Patch installer script with version string ---
    local patched_installer="${APORTS_SCRIPTS}/installer.sh"
    cp "${BUILD_DIR}/installer.sh" "$patched_installer"
    sed -i "s|@OPENWRT_VERSION@|${openwrt_version}|g" "$patched_installer"

    # --- Copy build scripts into aports scripts directory ---
    # mkimage.sh sources profile and genapkovl scripts from the same directory.
    cp "${BUILD_DIR}/scripts/mkimg.openwrt.sh"      "${APORTS_SCRIPTS}/"
    cp "${BUILD_DIR}/scripts/genapkovl-openwrt.sh"  "${APORTS_SCRIPTS}/"
    chmod +x "${APORTS_SCRIPTS}/genapkovl-openwrt.sh"

    mkdir -p "$OUTPUT_DIR"

    # --- Build the Alpine ISO ---
    echo "Building ISO..."
    cd "$APORTS_SCRIPTS"
    sh mkimage.sh \
        --tag "$ALPINE_VERSION" \
        --outdir "$OUTPUT_DIR" \
        --arch x86_64 \
        --profile openwrt \
        --repository "${ALPINE_MIRROR}/${ALPINE_VERSION}/main" \
        --repository "${ALPINE_MIRROR}/${ALPINE_VERSION}/community"

    local base_iso
    base_iso=$(find "$OUTPUT_DIR" -name "alpine-openwrt-*.iso" | head -1)
    if [[ -z "$base_iso" ]]; then
        # mkimage names may vary; grab any ISO produced
        base_iso=$(find "$OUTPUT_DIR" -name "*.iso" | head -1)
    fi
    if [[ -z "$base_iso" ]]; then
        echo "ERROR: mkimage.sh did not produce an ISO." >&2
        exit 1
    fi
    echo "Base ISO: $base_iso"

    local final_iso="${OUTPUT_DIR}/openwrt-x86-installer.iso"

    # --- Inject the bundled OpenWrt image into the ISO ---
    if [[ -f "${BUILD_DIR}/openwrt-image/openwrt-bundled.img.gz" ]]; then
        echo "Injecting bundled OpenWrt image into ISO..."
        xorriso \
            -indev "$base_iso" \
            -outdev "$final_iso" \
            -map "${BUILD_DIR}/openwrt-image/openwrt-bundled.img.gz" /openwrt-bundled.img.gz \
            -map "${BUILD_DIR}/openwrt-image/version.txt"            /openwrt-version.txt \
            -boot_image any replay \
            -commit_eject none

        # Remove the intermediate ISO if injection produced a new file
        if [[ "$base_iso" != "$final_iso" ]]; then
            rm -f "$base_iso"
        fi
    else
        echo "No bundled image — renaming base ISO."
        mv "$base_iso" "$final_iso"
    fi

    # Write version file to output dir so CI can read it without re-running the container
    cp "${BUILD_DIR}/openwrt-image/version.txt" "${OUTPUT_DIR}/openwrt-version.txt" 2>/dev/null || true

    echo ""
    echo "Done."
    ls -lh "$final_iso"
    echo ""
    echo "Write to USB:  dd if=$final_iso of=/dev/sdX bs=4M status=progress"
    echo "               (replace /dev/sdX with your USB device)"
}

main
