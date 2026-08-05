DOCKER_IMAGE := openwrt-installer-builder
OUTPUT_DIR   := dist

# Optional: path to a public key file (e.g. ~/.ssh/id_ed25519.pub) to also
# bake into the ISO as /root/.ssh/authorized_keys. Not required for SSH
# access — root login is passwordless by default on this installer image.
SSH_AUTHORIZED_KEYS ?=

.PHONY: all iso clean dist-clean

all: iso

## Build the installer ISO (output goes to ./dist/)
## Usage: make iso [SSH_AUTHORIZED_KEYS=~/.ssh/id_ed25519.pub]
iso:
	docker build --tag $(DOCKER_IMAGE) .
	mkdir -p $(OUTPUT_DIR)
	docker run --rm \
		--volume "$(CURDIR)/$(OUTPUT_DIR):/output" \
		--env OUTPUT_DIR=/output \
		$(if $(SSH_AUTHORIZED_KEYS),--volume "$(abspath $(SSH_AUTHORIZED_KEYS)):/build/authorized_keys:ro") \
		$(DOCKER_IMAGE)
	@echo ""
	@echo "ISO ready: $(OUTPUT_DIR)/openwrt-x86-installer.iso"
	@echo ""
	@echo "Write to USB (replace /dev/sdX with your USB device):"
	@echo "  sudo dd if=$(OUTPUT_DIR)/openwrt-x86-installer.iso of=/dev/sdX bs=4M status=progress"

## Remove built ISO
clean:
	rm -rf $(OUTPUT_DIR)

## Remove built ISO and Docker image
dist-clean: clean
	docker rmi -f $(DOCKER_IMAGE) 2>/dev/null || true
