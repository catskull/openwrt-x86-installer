#!/bin/sh
# mkimg.openwrt.sh — Alpine mkimage profile for the OpenWrt x86 Installer ISO
#
# Extends the standard Alpine profile and adds the packages and overlay
# needed by the TUI installer.

profile_openwrt() {
	profile_standard

	title="OpenWrt x86 Installer"
	desc="Bootable installer for OpenWrt on x86 systems (based on Alpine Linux)"
	image_ext="iso"
	arch="x86_64"

	# Extra packages beyond the standard profile.
	# The apkovl (auto-login + installer) is injected manually by build-iso.sh
	# rather than via this variable, so we have explicit control over its contents.
	# These are cached on the ISO so installation works without internet.
	apks="$apks
		bash
		dialog
		wget
		pv
		util-linux
		util-linux-misc
		coreutils
		gzip
		parted
	"

	# alpine_dev tells the initramfs where to find APK packages and the
	# apkovl on the boot media (required for the overlay to be applied).
	kernel_cmdline="alpine_dev=cdrom:iso9660 quiet modules=loop,squashfs,sd-mod,usb-storage,af_packet"
}
