# Build environment for the OpenWrt x86 Installer ISO.
# Based on Alpine Linux — uses the same mkimage.sh toolchain that Alpine
# uses to build its own official ISOs.

FROM alpine:3.21

# Build tools required by mkimage.sh
RUN apk add --no-cache \
    abuild \
    alpine-conf \
    squashfs-tools \
    xorriso \
    mtools \
    grub \
    grub-efi \
    syslinux \
    dosfstools \
    fakeroot \
    bash \
    wget \
    git \
    coreutils \
    openssl

# Clone only the scripts/ directory from aports (mkimage.sh + base profiles)
RUN git clone --depth=1 --filter=blob:none --sparse \
        https://gitlab.alpinelinux.org/alpine/aports.git /aports \
    && cd /aports \
    && git sparse-checkout set scripts

# Generate a throw-away RSA key pair for signing the ISO's APK index.
# abuild-sign (called by mkimage.sh) reads PACKAGER_PRIVKEY from abuild.conf.
# We use openssl directly to avoid the abuild-keygen user/group dance.
RUN mkdir -p /root/.abuild \
    && openssl genrsa -out /root/.abuild/build.rsa 2048 2>/dev/null \
    && openssl rsa -in /root/.abuild/build.rsa -pubout \
           -out /root/.abuild/build.rsa.pub 2>/dev/null \
    && cp /root/.abuild/build.rsa.pub /etc/apk/keys/ \
    && printf 'PACKAGER_PRIVKEY=/root/.abuild/build.rsa\n' > /root/.abuild/abuild.conf

WORKDIR /build

# Copy source files
COPY installer.sh      ./
COPY scripts/          ./scripts/

# Download the latest stable OpenWrt image at Docker build time so it is
# baked into the layer cache and the ISO build step stays fast.
RUN /build/scripts/fetch-openwrt.sh

# The CMD builds the ISO and writes it to /output (mounted by the caller).
CMD ["/build/scripts/build-iso.sh"]
