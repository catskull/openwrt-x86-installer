#!/usr/bin/env bash
# fetch-openwrt.sh
#
# Downloads the latest stable OpenWrt x86-64 EFI image at ISO build time.
# The image is stored in OUTPUT_DIR and later injected into the ISO root so
# the installer can read it from the boot media without extracting it to RAM.

set -euo pipefail

RELEASES_URL="https://downloads.openwrt.org/releases/"
BASE_URL="https://downloads.openwrt.org/releases"
IMAGE_TYPE="ext4-combined-efi"
OUTPUT_DIR="${OUTPUT_DIR:-/build/openwrt-image}"

get_latest_version() {
    wget -qO- "$RELEASES_URL" \
        | grep -oE 'href="[0-9]+\.[0-9]+\.[^"]*/"' \
        | sed 's|href="||; s|/"||' \
        | grep -vE 'rc|alpha|beta|SNAPSHOT' \
        | sort -V -r \
        | head -1
}

main() {
    local version
    version=$(get_latest_version)

    if [[ -z "$version" ]]; then
        echo "ERROR: Could not determine latest OpenWrt stable version." >&2
        exit 1
    fi

    echo "Latest OpenWrt stable release: $version"

    local filename="openwrt-${version}-x86-64-generic-${IMAGE_TYPE}.img.gz"
    local url="${BASE_URL}/${version}/targets/x86/64/${filename}"
    local sums_url="${BASE_URL}/${version}/targets/x86/64/sha256sums"

    mkdir -p "$OUTPUT_DIR"

    echo "Downloading: $url"
    wget -q --show-progress -O "${OUTPUT_DIR}/openwrt-bundled.img.gz" "$url"

    echo "Verifying checksum..."
    local sums_file="${OUTPUT_DIR}/sha256sums"
    wget -qO "$sums_file" "$sums_url"

    local expected
    expected=$(grep "$filename" "$sums_file" | awk '{print $1}')

    if [[ -z "$expected" ]]; then
        echo "WARNING: Checksum for $filename not found in sha256sums." >&2
    else
        local actual
        actual=$(sha256sum "${OUTPUT_DIR}/openwrt-bundled.img.gz" | awk '{print $1}')
        if [[ "$expected" != "$actual" ]]; then
            echo "ERROR: Checksum mismatch!" >&2
            echo "  Expected: $expected" >&2
            echo "  Got:      $actual" >&2
            exit 1
        fi
        echo "Checksum OK."
    fi

    rm -f "$sums_file"
    echo "$version" > "${OUTPUT_DIR}/version.txt"
    echo "Bundled OpenWrt version: $version"
}

main
