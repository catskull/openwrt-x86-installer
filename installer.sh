#!/usr/bin/env bash
# OpenWrt x86 Installer
# TUI installer using dialog

set -euo pipefail

BUNDLED_VERSION="@OPENWRT_VERSION@"
RELEASES_URL="https://downloads.openwrt.org/releases/"
RELEASES_BASE="https://downloads.openwrt.org/releases"
SNAPSHOT_BASE="https://downloads.openwrt.org/snapshots/targets/x86/64"
WORK_DIR="/tmp/openwrt-install"

# ---- Locate bundled image on boot media ----
find_bundled_image() {
    for mp in /media/cdrom /media/usb /media/sda /media/sda1 /media/sdb /media/sdb1 /media/sr0; do
        if [[ -f "${mp}/openwrt-bundled.img.gz" ]]; then
            echo "${mp}/openwrt-bundled.img.gz"
            return 0
        fi
    done
    return 1
}

# ---- Dependency check ----
check_deps() {
    local missing=()
    for cmd in dialog wget pv gzip dd lsblk sha256sum; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        dialog --title "Missing Dependencies" \
               --msgbox "The following commands are missing:\n\n  ${missing[*]}\n\nCheck your installation." \
               10 60
        exit 1
    fi
}

# ---- Disk selection ----
get_disks() {
    # Collect block device names that have mounted partitions (skip these)
    local busy_devs
    busy_devs=$(lsblk -rno PKNAME,MOUNTPOINT 2>/dev/null \
                | awk '$2 != "" && $1 != "" {print $1}' \
                | sort -u)

    lsblk -d -n -o NAME,SIZE,MODEL,TRAN 2>/dev/null \
        | grep -vE '^(loop|sr)' \
        | while read -r name size model tran; do
            # Skip devices with any mounted filesystem
            if echo "$busy_devs" | grep -qxF "$name"; then
                continue
            fi
            if lsblk -rno MOUNTPOINT "/dev/$name" 2>/dev/null | grep -q .; then
                continue
            fi
            model="${model:-(unknown)}"
            tran="${tran:-(unknown)}"
            printf '%s\t%s  %s  [%s]\n' "$name" "$size" "$model" "$tran"
        done
}

select_disk() {
    local disks_raw
    disks_raw=$(get_disks)

    if [[ -z "$disks_raw" ]]; then
        dialog --title "No Disks Found" \
               --msgbox "No suitable target disks found.\n\nEnsure the target disk is connected\nand is not the current boot device." \
               10 60
        return 1
    fi

    local menu_items=()
    while IFS=$'\t' read -r name desc; do
        menu_items+=("$name" "$desc")
    done <<< "$disks_raw"

    dialog --title "Select Target Disk" \
           --menu "Choose the disk to install OpenWrt on.\n\nWARNING: All data on the selected disk will be erased!" \
           18 72 8 \
           "${menu_items[@]}" \
           3>&1 1>&2 2>&3
}

# ---- Version selection ----
fetch_stable_versions() {
    wget -qO- --timeout=15 "$RELEASES_URL" 2>/dev/null \
        | grep -oE 'href="[0-9]+\.[0-9]+\.[^"]*/"' \
        | sed 's|href="||; s|/"||' \
        | grep -vE 'rc|alpha|beta|SNAPSHOT' \
        | sort -V \
        | tail -15
}

check_network() {
    # Quick connectivity check with a short timeout so we fail fast
    # rather than hanging when no network is available.
    if ! wget -q --spider --timeout=5 "$RELEASES_URL" 2>/dev/null; then
        dialog --title "No Internet Access" \
               --msgbox "Cannot reach downloads.openwrt.org.\n\nCheck that a network cable is connected\nand DHCP has assigned an address:\n\n  ip addr show\n  udhcpc -i eth0" \
               12 60
        return 1
    fi
}

fetch_rc_versions() {
    wget -qO- --timeout=15 "$RELEASES_URL" 2>/dev/null \
        | grep -oE 'href="[0-9]+\.[0-9]+\.[^"]*-rc[^"]*/"' \
        | sed 's|href="||; s|/"||' \
        | sort -V \
        | tail -10
}

select_version() {
    local has_bundled=false
    local bundled_path
    if bundled_path=$(find_bundled_image 2>/dev/null); then
        has_bundled=true
    fi

    local menu_items=()
    if [[ "$has_bundled" == "true" ]]; then
        menu_items+=("bundled" "${BUNDLED_VERSION}  (bundled — no download needed)")
    fi
    menu_items+=(
        "stable"   "Stable release  (choose version, requires internet)"
        "rc"       "Release candidate  (choose version, requires internet)"
        "snapshot" "Development snapshot  (latest, requires internet)"
    )

    dialog --title "Select OpenWrt Version" \
           --menu "Choose the version to install:" \
           16 72 6 \
           "${menu_items[@]}" \
           3>&1 1>&2 2>&3
}

select_release_version() {
    local kind="$1"  # stable | rc

    dialog --title "Fetching Releases" \
           --infobox "Fetching release list from downloads.openwrt.org..." \
           5 58

    local versions
    if [[ "$kind" == "rc" ]]; then
        versions=$(fetch_rc_versions)
    else
        versions=$(fetch_stable_versions)
    fi

    if [[ -z "$versions" ]]; then
        dialog --title "Error" \
               --msgbox "Could not fetch release list.\n\nCheck your internet connection." \
               8 52
        return 1
    fi

    local menu_items=()
    while IFS= read -r ver; do
        menu_items+=("$ver" "OpenWrt $ver")
    done <<< "$versions"

    dialog --title "Select Version" \
           --menu "Available releases:" \
           20 65 12 \
           "${menu_items[@]}" \
           3>&1 1>&2 2>&3
}

select_image_type() {
    dialog --title "Select Image Type" \
           --menu "Choose the OpenWrt filesystem type:" \
           13 72 2 \
           "ext4"     "ext4      — Read-write filesystem (recommended)" \
           "squashfs" "squashfs  — Read-only with overlay, supports factory reset" \
           3>&1 1>&2 2>&3
}

# ---- Download ----
download_with_progress() {
    local url="$1"
    local dest="$2"
    local title="$3"

    if ! wget -q --spider --timeout=15 "$url" 2>/dev/null; then
        dialog --title "Error" \
               --msgbox "Cannot reach:\n$url\n\nCheck your internet connection." \
               9 72
        return 1
    fi

    local size
    size=$(wget --server-response --spider --timeout=15 "$url" 2>&1 \
           | grep -i "content-length" | awk '{print $2}' | tail -1 | tr -d '\r' || echo 0)
    size="${size:-0}"

    local fifo
    fifo=$(mktemp -u /tmp/dl-progress-XXXXXX)
    mkfifo "$fifo"

    dialog --title "$title" --gauge "Downloading..." 8 70 0 < "$fifo" &
    local dlg_pid=$!

    wget -qO- "$url" 2>/dev/null \
        | pv -n -s "$size" 2>"$fifo" \
        > "$dest"
    local rc=$?

    echo 100 > "$fifo" 2>/dev/null || true
    wait "$dlg_pid" 2>/dev/null || true
    rm -f "$fifo"

    if [[ $rc -ne 0 ]]; then
        dialog --title "Error" --msgbox "Download failed." 6 40
        return 1
    fi
}

# ---- Checksum verification ----
verify_checksum() {
    local image="$1"
    local sums_url="$2"
    local filename
    filename=$(basename "$image")

    dialog --title "Verifying" --infobox "Verifying checksum..." 5 40

    local sums_file
    sums_file=$(mktemp /tmp/sha256sums-XXXXXX)

    if wget -qO "$sums_file" "$sums_url" 2>/dev/null; then
        local expected
        expected=$(grep -E " \*?${filename}$" "$sums_file" | awk '{print $1}')
        if [[ -n "$expected" ]]; then
            local actual
            actual=$(sha256sum "$image" | awk '{print $1}')
            rm -f "$sums_file"
            if [[ "$expected" != "$actual" ]]; then
                dialog --title "Checksum Failed" \
                       --msgbox "Checksum verification FAILED.\n\nExpected: $expected\nGot:      $actual\n\nThe file may be corrupt. Please try again." \
                       12 72
                return 1
            fi
            dialog --title "Verified" --infobox "Checksum OK." 5 30
            sleep 1
            return 0
        fi
    fi

    rm -f "$sums_file"
    dialog --title "Warning" \
           --yesno "Could not verify checksum (sha256sums unavailable).\n\nContinue anyway?" \
           8 60 || return 1
}

# ---- Eject boot media ----
eject_boot_media() {
    # Unmount all known installer mount points
    for mp in /media/cdrom /media/usb /media/sda /media/sda1 /media/sdb /media/sdb1 /media/sr0; do
        if mountpoint -q "$mp" 2>/dev/null; then
            umount "$mp" 2>/dev/null || true
        fi
    done
    # Try to eject the CD-ROM
    eject /dev/sr0 2>/dev/null || true
}

# ---- Write image ----
write_image() {
    local image="$1"
    local device="$2"

    local uncompressed_size
    uncompressed_size=$(gzip -l "$image" 2>/dev/null | awk 'NR==2{print $2}' || echo 0)

    local fifo
    fifo=$(mktemp -u /tmp/write-progress-XXXXXX)
    mkfifo "$fifo"

    dialog --title "Installing OpenWrt" \
           --gauge "Writing to /dev/$device — do not remove boot media..." \
           8 70 0 < "$fifo" &
    local dlg_pid=$!

    gunzip -c "$image" \
        | pv -n -s "$uncompressed_size" 2>"$fifo" \
        | dd of="/dev/$device" bs=4M 2>/dev/null
    local rc=$?

    sync
    echo 100 > "$fifo" 2>/dev/null || true
    wait "$dlg_pid" 2>/dev/null || true
    rm -f "$fifo"

    if [[ $rc -ne 0 ]]; then
        dialog --title "Error" \
               --msgbox "Failed to write image to /dev/$device.\n\nCheck that the device is present and not write-protected." \
               9 65
        return 1
    fi
}

# ---- Main ----
main() {
    check_deps
    mkdir -p "$WORK_DIR"

    # Welcome
    dialog --title "OpenWrt x86 Installer" \
           --yesno "Welcome to the OpenWrt x86 Installer.\n\nThis tool will write an OpenWrt image to a disk of your choice.\n\nWARNING: All data on the selected disk will be permanently erased!\n\nContinue?" \
           12 70 || exit 0

    # Step 1: Disk
    local disk
    disk=$(select_disk) || exit 0

    # Step 2: Version
    local version_choice
    version_choice=$(select_version) || exit 0

    local image_path=""
    local version_label=""
    local image_type=""

    case "$version_choice" in
        bundled)
            image_path=$(find_bundled_image)
            version_label="${BUNDLED_VERSION} (bundled)"
            ;;
        stable|rc)
            check_network || exit 0
            local version
            version=$(select_release_version "$version_choice") || exit 0

            image_type=$(select_image_type) || exit 0

            local filename="openwrt-${version}-x86-64-generic-${image_type}-combined-efi.img.gz"
            local url="${RELEASES_BASE}/${version}/targets/x86/64/${filename}"
            local sums_url="${RELEASES_BASE}/${version}/targets/x86/64/sha256sums"

            image_path="${WORK_DIR}/${filename}"
            version_label="${version} (${image_type})"

            download_with_progress "$url" "$image_path" "Downloading OpenWrt $version" || exit 1
            verify_checksum "$image_path" "$sums_url" || exit 1
            ;;
        snapshot)
            check_network || exit 0
            image_type=$(select_image_type) || exit 0

            local filename="openwrt-x86-64-generic-${image_type}-combined-efi.img.gz"
            local url="${SNAPSHOT_BASE}/${filename}"
            local sums_url="${SNAPSHOT_BASE}/sha256sums"

            image_path="${WORK_DIR}/openwrt-snapshot-${image_type}.img.gz"
            version_label="Snapshot (${image_type})"

            download_with_progress "$url" "$image_path" "Downloading OpenWrt Snapshot" || exit 1
            verify_checksum "$image_path" "$sums_url" || exit 1
            ;;
    esac

    # Step 3: Confirm
    local disk_info
    disk_info=$(lsblk -d -n -o SIZE,MODEL "/dev/$disk" 2>/dev/null | head -1 || echo "(unknown)")

    dialog --title "Confirm Installation" \
           --defaultno \
           --yesno "Ready to install:\n\n  OpenWrt:  $version_label\n  Target:   /dev/$disk  $disk_info\n\nALL DATA ON /dev/$disk WILL BE PERMANENTLY ERASED!\n\nProceed with installation?" \
           13 70 || exit 0

    # Step 4: Write
    write_image "$image_path" "$disk" || exit 1

    # Step 5: Done
    dialog --title "Installation Complete" \
           --yesno "OpenWrt has been installed on /dev/$disk.\n\nThe installer will eject the boot media and power off.\nRemove the USB/CD before powering back on.\n\nPower off now?" \
           11 70 || { clear; echo "Installation complete. Remove boot media and reboot when ready."; return 0; }

    clear
    echo "Syncing..."
    sync
    eject_boot_media
    echo "Powering off..."
    poweroff
}

main "$@"
