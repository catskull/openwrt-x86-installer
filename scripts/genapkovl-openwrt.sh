#!/bin/sh
# genapkovl-openwrt.sh
#
# Called by mkimage.sh to generate the Alpine overlay (apkovl) for the
# OpenWrt installer ISO.  Output is a gzipped tar on stdout.

HOSTNAME="${1:-openwrt-installer}"
AUTHORIZED_KEYS_FILE="${2:-}"

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
openssh-server
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

# ---- /etc/ssh/sshd_config ----
# SSH is on by default for headless installs, with passwordless root login.
# This is intentional: the box only runs this installer image briefly, and
# the tradeoff is convenience over the install workflow. It does mean anyone
# who can reach the box on the network during that window gets a root shell
# with no credentials — do not leave the installer running/reachable longer
# than it takes to install, and treat untrusted networks accordingly.
mkdir -p "$tmp/etc/ssh"
cat > "$tmp/etc/ssh/sshd_config" <<'EOF'
# Managed by openwrt-x86-installer — do not hand-edit, changes are lost on reboot.
PermitRootLogin yes
PermitEmptyPasswords yes
PasswordAuthentication yes
EOF

# ---- /etc/init.d/rootnopasswd ----
# Clears the root password so PermitEmptyPasswords above actually allows
# login. Runs in the "boot" runlevel — strictly before "default" (which
# brings up networking and sshd) — so there's no window where sshd is
# reachable but the password hasn't been cleared yet.
mkdir -p "$tmp/etc/init.d"
cat > "$tmp/etc/init.d/rootnopasswd" <<'EOF'
#!/sbin/openrc-run
description="Clear the root password for passwordless console/SSH login"

depend() {
    before networking
    before sshd
}

start() {
    ebegin "Clearing root password (passwordless login enabled for this installer)"
    passwd -d root >/dev/null 2>&1
    eend 0
}
EOF
chmod 755 "$tmp/etc/init.d/rootnopasswd"
mkdir -p "$tmp/etc/runlevels/boot"
ln -sf /etc/init.d/rootnopasswd "$tmp/etc/runlevels/boot/rootnopasswd"

# ---- /root/.ssh/authorized_keys (optional) ----
# Not required for login (root has no password and PermitEmptyPasswords is
# on), but still supported for anyone who wants key-based access logged in
# their shell history instead of a bare `ssh root@host`.
if [ -n "$AUTHORIZED_KEYS_FILE" ] && [ -s "$AUTHORIZED_KEYS_FILE" ]; then
    mkdir -p "$tmp/root/.ssh"
    chmod 700 "$tmp/root/.ssh"
    cp "$AUTHORIZED_KEYS_FILE" "$tmp/root/.ssh/authorized_keys"
    chmod 600 "$tmp/root/.ssh/authorized_keys"
fi

# ---- /root/installer.sh ----
mkdir -p "$tmp/root"
cp /build/installer.sh "$tmp/root/installer.sh"
chmod 755 "$tmp/root/installer.sh"

# ---- /usr/local/bin/install-openwrt ----
mkdir -p "$tmp/usr/local/bin"
cat > "$tmp/usr/local/bin/install-openwrt" <<'EOF'
#!/bin/sh
exec /root/installer.sh "$@"
EOF
chmod 755 "$tmp/usr/local/bin/install-openwrt"

# ---- /root/autostart.sh ----
# Launched directly by getty.  Waits for APK to finish installing packages
# (dialog is our canary) before starting the installer.  After the installer
# exits for any reason, drop to a shell so the user is not trapped in a loop.
cat > "$tmp/root/autostart.sh" <<'EOF'
#!/bin/sh
export TERM="${TERM:-linux}"
while ! command -v dialog >/dev/null 2>&1; do
    printf '\033[2J\033[H'
    echo "Setting up, please wait..."
    sleep 2
done
clear
ips=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | tr '\n' ' ')
echo "SSH is up: ssh root@<ip>  (no password needed). Reachable at: ${ips:-no address yet}"
echo ""
/root/installer.sh || true
clear
echo ""
echo "Installer exited. To relaunch, run:  install-openwrt"
echo ""
exec /bin/sh
EOF
chmod 755 "$tmp/root/autostart.sh"

# ---- Enable networking and sshd at boot ----
mkdir -p "$tmp/etc/runlevels/default"
ln -sf /etc/init.d/networking "$tmp/etc/runlevels/default/networking"
ln -sf /etc/init.d/sshd "$tmp/etc/runlevels/default/sshd"

tar -c -C "$tmp" . | gzip -9n
