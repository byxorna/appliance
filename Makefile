IMAGE_NAME := reterminal-hifi-builder:latest
# Override with `make CONTAINER_ENGINE=docker <target>` to use Docker
CONTAINER_ENGINE := podman

BUILDER_UID := $(shell id -u)
BUILDER_GID := $(shell id -g)

CACHE_DIR := $(HOME)/.cache/reterminal-hifi-builder
DOWNLOADS_DIR := $(CACHE_DIR)/downloads
SSTATE_DIR := $(CACHE_DIR)/sstate

# Podman inherits ~/.docker/config.json credHelpers, which may reference
# helpers not installed on this host (e.g. ecr-login).  An empty auth file
# prevents Podman from trying to load them.
EMPTY_AUTH := $(CACHE_DIR)/.podman-auth.json

COMMON_RUN_FLAGS := \
	--rm -it \
	--authfile "$(EMPTY_AUTH)" \
	-v "$(CURDIR)":/workspace:Z \
	-v "$(DOWNLOADS_DIR)":/workspace/downloads:Z \
	-v "$(SSTATE_DIR)":/workspace/sstate-cache:Z \
	$(IMAGE_NAME)

.PHONY: image shell kas-shell clean

$(EMPTY_AUTH):
	@mkdir -p "$(dir $@)"
	@echo '{}' > "$@"

image: $(EMPTY_AUTH)
	@mkdir -p "$(DOWNLOADS_DIR)" "$(SSTATE_DIR)"
	$(CONTAINER_ENGINE) build \
		--authfile "$(EMPTY_AUTH)" \
		--build-arg BUILDER_UID=$(BUILDER_UID) \
		--build-arg BUILDER_GID=$(BUILDER_GID) \
		-t $(IMAGE_NAME) build/

shell: $(EMPTY_AUTH)
	@mkdir -p "$(DOWNLOADS_DIR)" "$(SSTATE_DIR)"
	$(CONTAINER_ENGINE) run $(COMMON_RUN_FLAGS) /bin/bash

kas-shell: $(EMPTY_AUTH)
	@mkdir -p "$(DOWNLOADS_DIR)" "$(SSTATE_DIR)"
	$(CONTAINER_ENGINE) run $(COMMON_RUN_FLAGS) kas shell kas/reterminal-hifi.yml

clean:
	$(CONTAINER_ENGINE) rmi $(IMAGE_NAME) || true
