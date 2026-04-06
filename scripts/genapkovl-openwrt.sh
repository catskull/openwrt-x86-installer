#!/bin/sh
# genapkovl-openwrt.sh
#
# Called by mkimage.sh to generate the Alpine overlay (apkovl) for the
# OpenWrt installer ISO.  Output is a gzipped tar on stdout.

HOSTNAME="${1:-openwrt-installer}"

cleanup() {
    rm -rf "$tmp"
}

tmp="$(mktemp -d)"
trap cleanup EXIT

# ---- /etc/hostname ----
mkdir -p "$tmp/etc"
printf '%s\n' "$HOSTNAME" > "$tmp/etc/hostname"

# ---- /etc/network/interfaces ----
# Bring up loopback and try DHCP on common interfaces so 'wget' works
# for downloading versions.
mkdir -p "$tmp/etc/network"
cat > "$tmp/etc/network/interfaces" <<'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

auto eth1
iface eth1 inet dhcp
EOF

# ---- /etc/apk/world ----
# Packages to install at boot from the ISO's local APK cache.
# Must stay in sync with the apks list in mkimg.openwrt.sh.
mkdir -p "$tmp/etc/apk"
cat > "$tmp/etc/apk/world" <<'EOF'
alpine-base
bash
dialog
wget
pv
util-linux
util-linux-misc
coreutils
gzip
parted
EOF

# ---- /etc/inittab ----
# Use busybox getty with -n (no login prompt) and -l (run program directly).
# agetty --autologin is not available until util-linux is installed by APK,
# which happens after init starts — so we use the always-present busybox getty.
cat > "$tmp/etc/inittab" <<'EOF'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default

tty1::respawn:/sbin/getty -n -l /root/autostart.sh 38400 tty1
tty2::respawn:/sbin/getty 38400 tty2
ttyS0::respawn:/sbin/getty -n -l /root/autostart.sh 115200 ttyS0

::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown
EOF

# ---- /root/installer.sh ----
mkdir -p "$tmp/root"
cp /build/installer.sh "$tmp/root/installer.sh"
chmod 755 "$tmp/root/installer.sh"

# ---- /root/autostart.sh ----
# Launched directly by getty.  Waits for APK to finish installing packages
# (dialog is our canary) before starting the installer.
cat > "$tmp/root/autostart.sh" <<'EOF'
#!/bin/sh
export TERM="${TERM:-linux}"
while ! command -v dialog >/dev/null 2>&1; do
    printf '\033[2J\033[H'
    echo "Setting up, please wait..."
    sleep 2
done
clear
exec /root/installer.sh
EOF
chmod 755 "$tmp/root/autostart.sh"

# ---- Enable networking at boot ----
mkdir -p "$tmp/etc/runlevels/default"
ln -sf /etc/init.d/networking "$tmp/etc/runlevels/default/networking"

tar -c -C "$tmp" . | gzip -9n
