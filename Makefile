BUILD := reterminal-hifi
KAS_CONFIG := kas/$(BUILD).yaml

IMAGE_NAME := appliance-builder:latest
# Override with `make CONTAINER_ENGINE=docker <target>` to use Docker
CONTAINER_ENGINE := podman
MACHINE := $(shell awk '/^machine:/ {print $$2}' $(KAS_CONFIG))
IMAGE := $(shell awk '/^target:/ {print $$2}' $(KAS_CONFIG) kas/common.yaml | head -1)
ARTIFACTS_DIR := $(CURDIR)/artifacts
ARTIFACT_PREFIX := $(BUILD)-$(IMAGE)-$(MACHINE)

BUILDER_UID := $(shell id -u)
BUILDER_GID := $(shell id -g)

CACHE_DIR := $(CURDIR)/.cache
DOWNLOADS_DIR := $(CACHE_DIR)/downloads
SSTATE_DIR := $(CACHE_DIR)/sstate
REPO_REF_DIR := $(CACHE_DIR)/repos
TMPDIR_VOL := appliance-$(BUILD)-tmpdir

# Podman inherits ~/.docker/config.json credHelpers, which may reference
# helpers not installed on this host (e.g. ecr-login).  An empty auth file
# prevents the container engine from trying to load them.
EMPTY_AUTH := $(CACHE_DIR)/.podman-auth.json

# macOS filesystems (HFS+/APFS) are case-insensitive, which Yocto rejects.
# TMPDIR is placed on a named volume so it lives on the VM's case-sensitive
# ext4 filesystem. The volume persists across runs (fast incremental builds)
# and is cleaned by `make clean`.
COMMON_RUN_FLAGS := \
	--rm -it \
	--authfile "$(EMPTY_AUTH)" \
	-v "$(CURDIR)":/workspace:Z \
	-v "$(DOWNLOADS_DIR)":/workspace/downloads:Z \
	-v "$(SSTATE_DIR)":/workspace/sstate-cache:Z \
	-v "$(REPO_REF_DIR)":/workspace/repos:Z \
	-v "$(TMPDIR_VOL)":/workspace/build/tmp:Z \
	-e KAS_REPO_REF_DIR=/workspace/repos \
	$(IMAGE_NAME)

.PHONY: image shell kas-shell check build status clean

$(EMPTY_AUTH):
	@mkdir -p "$(dir $@)"
	@echo '{}' > "$@"

image: $(EMPTY_AUTH)
	@mkdir -p "$(DOWNLOADS_DIR)" "$(SSTATE_DIR)" "$(REPO_REF_DIR)"
	$(CONTAINER_ENGINE) build \
		--authfile "$(EMPTY_AUTH)" \
		--build-arg BUILDER_UID=$(BUILDER_UID) \
		--build-arg BUILDER_GID=$(BUILDER_GID) \
		-t $(IMAGE_NAME) build/

shell: $(EMPTY_AUTH)
	@mkdir -p "$(DOWNLOADS_DIR)" "$(SSTATE_DIR)" "$(REPO_REF_DIR)"
	$(CONTAINER_ENGINE) run $(COMMON_RUN_FLAGS) /bin/bash

kas-shell: $(EMPTY_AUTH) image
	@mkdir -p "$(DOWNLOADS_DIR)" "$(SSTATE_DIR)" "$(REPO_REF_DIR)"
	$(CONTAINER_ENGINE) run $(COMMON_RUN_FLAGS) kas shell $(KAS_CONFIG)

check: $(EMPTY_AUTH) image
	@mkdir -p "$(DOWNLOADS_DIR)" "$(SSTATE_DIR)" "$(REPO_REF_DIR)"
	$(CONTAINER_ENGINE) run $(COMMON_RUN_FLAGS) kas shell $(KAS_CONFIG) -c 'bitbake -p'

build: check
	@mkdir -p "$(DOWNLOADS_DIR)" "$(SSTATE_DIR)" "$(REPO_REF_DIR)"
	$(eval BUILD_START := $(shell date +%s))
	$(CONTAINER_ENGINE) run $(COMMON_RUN_FLAGS) kas shell $(KAS_CONFIG) -c 'bitbake -c build $(IMAGE)'
	@mkdir -p "$(ARTIFACTS_DIR)"
	$(CONTAINER_ENGINE) run $(COMMON_RUN_FLAGS) bash -c '\
		SRC=/workspace/build/tmp/deploy/images/$(MACHINE); \
		DST=/workspace/artifacts; \
		cp -vL "$$SRC"/$(IMAGE)-$(MACHINE).rootfs.wic.bz2 "$$DST/$(ARTIFACT_PREFIX).wic.bz2" 2>/dev/null \
			|| cp -vL "$$SRC"/$(IMAGE)-$(MACHINE).rootfs.wic "$$DST/$(ARTIFACT_PREFIX).wic" 2>/dev/null \
			|| { echo "ERROR: No .wic or .wic.bz2 image found in $$SRC"; exit 1; }; \
		cp -vL "$$SRC"/$(IMAGE)-$(MACHINE).rootfs.manifest "$$DST/$(ARTIFACT_PREFIX).manifest" 2>/dev/null || true'
	@# Sanity check: image mtime must be later than build start
	@for f in "$(ARTIFACTS_DIR)"/$(ARTIFACT_PREFIX).wic.bz2 \
	          "$(ARTIFACTS_DIR)"/$(ARTIFACT_PREFIX).wic; do \
		if [ -f "$$f" ]; then \
			MTIME=$$(stat -f %m "$$f" 2>/dev/null || stat -c %Y "$$f" 2>/dev/null); \
			if [ "$$MTIME" -lt "$(BUILD_START)" ]; then \
				echo "ERROR: $$f is stale (mtime $$MTIME < build start $(BUILD_START))"; \
				exit 1; \
			fi; \
			break; \
		fi; \
	done
	@# Generate build-info sidecar
	@GIT_SHA=$$(git -C "$(CURDIR)" rev-parse --short HEAD 2>/dev/null || echo "unknown"); \
	GIT_DIRTY=$$(git -C "$(CURDIR)" diff --quiet 2>/dev/null && echo "" || echo " (dirty)"); \
	GIT_BRANCH=$$(git -C "$(CURDIR)" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"); \
	INFO="$(ARTIFACTS_DIR)/$(ARTIFACT_PREFIX).build-info"; \
	{ \
		echo "build:    $(BUILD)"; \
		echo "image:    $(IMAGE)"; \
		echo "machine:  $(MACHINE)"; \
		echo "config:   $(KAS_CONFIG)"; \
		echo "branch:   $$GIT_BRANCH"; \
		echo "commit:   $${GIT_SHA}$${GIT_DIRTY}"; \
		echo "date:     $$(date -Iseconds)"; \
		echo ""; \
		for f in "$(ARTIFACTS_DIR)"/$(ARTIFACT_PREFIX).*; do \
			[ -f "$$f" ] && [ "$$f" != "$$INFO" ] && shasum -a 256 "$$f"; \
		done; \
	} > "$$INFO"; \
	echo ""; cat "$$INFO"; echo ""

status:
	@CIDS=$$($(CONTAINER_ENGINE) ps -q --filter ancestor=$(IMAGE_NAME)); \
	if [ -z "$$CIDS" ]; then \
		echo "No build container running."; \
	else \
		for CID in $$CIDS; do \
			echo "=== Container $$CID ==="; \
			$(CONTAINER_ENGINE) exec "$$CID" bash -c ' \
				LOG=$$(find /workspace/build -path "*/log/cooker/*/console-latest.log" -printf "%T@ %p\n" 2>/dev/null \
					| sort -rn | head -1 | cut -d" " -f2-); \
				if [ -n "$$LOG" ]; then \
					tail -30 "$$LOG"; \
				else \
					echo "No bitbake log found."; \
				fi; \
				PIDS=$$(pgrep -f "bitbake" 2>/dev/null | tr "\n" " "); \
				if [ -n "$$PIDS" ]; then \
					echo "--- bitbake running (PIDs: $$PIDS) ---"; \
				fi'; \
		done; \
	fi

clean:
	$(CONTAINER_ENGINE) rmi $(IMAGE_NAME) || true
	$(CONTAINER_ENGINE) volume rm $(TMPDIR_VOL) || true
	rm -rf "$(CACHE_DIR)" "$(ARTIFACTS_DIR)" build/repos || :
