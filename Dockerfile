# Build environment for the OpenWrt x86 Installer ISO.
# Based on Alpine Linux — uses the same mkimage.sh toolchain that Alpine
# uses to build its own official ISOs.

FROM alpine:3.21

# Build tools required by mkimage.sh
RUN apk add --no-cache \
    alpine-sdk \
    abuild \
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
    coreutils

# Clone only the scripts/ directory from aports (mkimage.sh + base profiles)
RUN git clone --depth=1 --filter=blob:none --sparse \
        https://gitlab.alpinelinux.org/alpine/aports.git /aports \
    && cd /aports \
    && git sparse-checkout set scripts

# mkimage.sh must be run by a user in the 'abuild' group.
# Generate a throw-away RSA signing key for the build.
RUN addgroup -g 1000 builder \
    && adduser -D -G abuild -G builder -u 1000 builder

USER builder
RUN abuild-keygen -a -i -n
USER root

# Trust the generated public key system-wide (needed by APK inside the build)
RUN cp /home/builder/.abuild/*.pub /etc/apk/keys/

# mkimage.sh is run as root but needs access to the signing key.
# Copy the full key pair to root's abuild config.
RUN mkdir -p /root/.abuild \
    && cp /home/builder/.abuild/* /root/.abuild/ \
    && echo "PACKAGER_PRIVKEY=$(ls /root/.abuild/*.rsa)" > /root/.abuild/abuild.conf

WORKDIR /build

# Copy source files
COPY installer.sh      ./
COPY scripts/          ./scripts/

# Download the latest stable OpenWrt image at Docker build time so it is
# baked into the layer cache and the ISO build step stays fast.
RUN /build/scripts/fetch-openwrt.sh

# The CMD builds the ISO and writes it to /output (mounted by the caller).
CMD ["/build/scripts/build-iso.sh"]
