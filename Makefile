VARIANT ?= reterminal-hifi
VARIANTS := $(patsubst kas/variant-%.yaml,%,$(wildcard kas/variant-*.yaml))
KAS_CONFIG := kas/variant-$(VARIANT).yaml
KAS_DEPENDENCIES := build-image

IMAGE_NAME := appliance-builder:latest
# Override with `make CONTAINER_ENGINE=docker <target>` to use Docker
CONTAINER_ENGINE := podman
MACHINE := $(shell awk '/^machine:/ {print $$2}' $(KAS_CONFIG))
IMAGE := $(shell awk '/^target:/ {print $$2}' $(KAS_CONFIG) kas/common.yaml | head -1)
ARTIFACTS_DIR := $(CURDIR)/artifacts
ARTIFACT_PREFIX := $(VARIANT)-$(IMAGE)-$(MACHINE)

BUILDER_UID := $(shell id -u)
BUILDER_GID := $(shell id -g)

# Version from nearest git tag (e.g. "0.1.0-3-gbce1bc4-dirty")
APPLIANCE_VERSION := $(shell git -C "$(CURDIR)" describe --tags --long --always --dirty 2>/dev/null | sed 's/^v//')
APPLIANCE_HOME_URL ?= $(shell git -C "$(CURDIR)" remote get-url origin 2>/dev/null | sed 's/\.git$$//; s|^git@\([^:]*\):|https://\1/|')
APPLIANCE_BUG_REPORT_URL ?= $(addsuffix /issues,$(APPLIANCE_HOME_URL))

CACHE_DIR := $(CURDIR)/.cache
DOWNLOADS_DIR := $(CACHE_DIR)/downloads
SSTATE_DIR := $(CACHE_DIR)/sstate
REPO_REF_DIR := $(CACHE_DIR)/repos
BUILD_VOL := appliance-$(VARIANT)-build

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
	-v "$(BUILD_VOL)":/workspace/build:Z \
	-e KAS_REPO_REF_DIR=/workspace/repos \
	-e APPLIANCE_VERSION="$(APPLIANCE_VERSION)" \
	-e APPLIANCE_VARIANT="$(VARIANT)" \
	-e APPLIANCE_HOME_URL="$(APPLIANCE_HOME_URL)" \
	-e APPLIANCE_BUG_REPORT_URL="$(APPLIANCE_BUG_REPORT_URL)" \
	$(IMAGE_NAME)

# --- App container images ---------------------------------------------------
# Each subdirectory under containers/ with a Dockerfile becomes a buildable
# app image.  Tag is appliance-<name>:latest by default.  Set
# CONTAINER_REGISTRY to push to a remote registry, e.g.
#   make CONTAINER_REGISTRY=ghcr.io/myorg build-containers
CONTAINER_REGISTRY ?=
CONTAINER_PLATFORM ?= linux/arm64
CONTAINER_DIRS := $(wildcard containers/*/Dockerfile)
CONTAINER_NAMES := $(patsubst containers/%/Dockerfile,%,$(CONTAINER_DIRS))
_registry_prefix = $(if $(CONTAINER_REGISTRY),$(CONTAINER_REGISTRY)/,)
CONTAINER_TAGS := $(foreach n,$(CONTAINER_NAMES),$(_registry_prefix)appliance-$(n):latest)

.PHONY: build-containers save-containers $(addprefix build-container-,$(CONTAINER_NAMES))

build-containers: $(addprefix build-container-,$(CONTAINER_NAMES)) ## Build all app container images
save-containers: $(addprefix save-container-,$(CONTAINER_NAMES)) ## Save all app container images as tarballs

define CONTAINER_RULES
build-container-$(1): $(EMPTY_AUTH) ## Build container image for $(1)
	$(CONTAINER_ENGINE) build \
		--authfile "$$(EMPTY_AUTH)" \
		--platform $$(CONTAINER_PLATFORM) \
		-t $$(_registry_prefix)appliance-$(1):latest \
		containers/$(1)/

save-container-$(1): build-container-$(1) ## Save $(1) container image as tarball
	@mkdir -p "$$(ARTIFACTS_DIR)"
	$$(CONTAINER_ENGINE) save \
		--format oci-archive \
		$$(_registry_prefix)appliance-$(1):latest \
		-o $$(ARTIFACTS_DIR)/appliance-$(1)-latest.tar
	@echo "$$(ARTIFACTS_DIR)/appliance-$(1)-latest.tar"
endef

$(foreach n,$(CONTAINER_NAMES),$(eval $(call CONTAINER_RULES,$(n))))

.PHONY: shell kas-shell check build build-image build-update build-firmware build-all release status clean clean-cache clean-cache-all rpiboot _build-info print-variants print-machines $(addprefix x-rebuild-redeploy-,$(VARIANTS))

# Known artifact extensions produced by build and build-update targets.
# Only these are checksummed in the build-info sidecar.
ARTIFACT_EXTS := .wic.bz2 .wic .manifest .raucb

build: check build-firmware build-update ## Full build: parse-check, firmware image, and RAUC update bundle

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

print-variants: ## List all available variants (one per line)
	@for v in $(VARIANTS); do echo "$$v"; done

print-machines: ## List all unique machines across variants (one per line)
	@awk '/^machine:/ {print $$2}' kas/variant-*.yaml | sort -u

$(EMPTY_AUTH):
	@mkdir -p "$(dir $@)"
	@echo '{}' > "$@"

build-image: $(EMPTY_AUTH) ## Build the OCI builder container image
	@mkdir -p "$(DOWNLOADS_DIR)" "$(SSTATE_DIR)" "$(REPO_REF_DIR)"
	$(CONTAINER_ENGINE) build \
		--authfile "$(EMPTY_AUTH)" \
		--build-arg BUILDER_UID=$(BUILDER_UID) \
		--build-arg BUILDER_GID=$(BUILDER_GID) \
		-t $(IMAGE_NAME) build/

shell: $(EMPTY_AUTH) ## Interactive bash shell in the build container
	@mkdir -p "$(DOWNLOADS_DIR)" "$(SSTATE_DIR)" "$(REPO_REF_DIR)"
	$(CONTAINER_ENGINE) run $(COMMON_RUN_FLAGS) /bin/bash

kas-shell: $(EMPTY_AUTH) $(KAS_DEPENDENCIES) ## Interactive kas shell with the project config loaded
	@mkdir -p "$(DOWNLOADS_DIR)" "$(SSTATE_DIR)" "$(REPO_REF_DIR)"
	$(CONTAINER_ENGINE) run $(COMMON_RUN_FLAGS) kas shell $(KAS_CONFIG)

check: $(EMPTY_AUTH) $(KAS_DEPENDENCIES) ## Parse-validate all layers and configs (no build)
	@mkdir -p "$(DOWNLOADS_DIR)" "$(SSTATE_DIR)" "$(REPO_REF_DIR)"
	$(CONTAINER_ENGINE) run $(COMMON_RUN_FLAGS) kas shell $(KAS_CONFIG) -c 'bitbake -p'

build-firmware: $(KAS_DEPENDENCIES) ## Build the WIC disk image and copy artifacts
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
	@$(MAKE) --no-print-directory _build-info

build-update: check ## Build the RAUC update bundle (.raucb)
	@mkdir -p "$(DOWNLOADS_DIR)" "$(SSTATE_DIR)" "$(REPO_REF_DIR)"
	$(eval BUILD_START := $(shell date +%s))
	$(CONTAINER_ENGINE) run $(COMMON_RUN_FLAGS) kas shell $(KAS_CONFIG) -c 'bitbake update-bundle'
	@mkdir -p "$(ARTIFACTS_DIR)"
	$(CONTAINER_ENGINE) run $(COMMON_RUN_FLAGS) bash -c '\
		SRC=/workspace/build/tmp/deploy/images/$(MACHINE); \
		DST=/workspace/artifacts; \
		cp -vL "$$SRC"/update-bundle-$(MACHINE).raucb "$$DST/$(ARTIFACT_PREFIX).raucb" \
			|| { echo "ERROR: No .raucb bundle found in $$SRC"; exit 1; }'
	@# Sanity check: bundle mtime must be later than build start
	@f="$(ARTIFACTS_DIR)/$(ARTIFACT_PREFIX).raucb"; \
	MTIME=$$(stat -f %m "$$f" 2>/dev/null || stat -c %Y "$$f" 2>/dev/null); \
	if [ "$$MTIME" -lt "$(BUILD_START)" ]; then \
		echo "ERROR: $$f is stale (mtime $$MTIME < build start $(BUILD_START))"; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory _build-info

_build-info:
	@GIT_SHA=$$(git -C "$(CURDIR)" rev-parse --short HEAD 2>/dev/null || echo "unknown"); \
	GIT_DIRTY=$$(git -C "$(CURDIR)" diff --quiet 2>/dev/null && echo "" || echo " (dirty)"); \
	GIT_BRANCH=$$(git -C "$(CURDIR)" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"); \
	INFO="$(ARTIFACTS_DIR)/$(ARTIFACT_PREFIX).build-info"; \
	{ \
		echo "variant:  $(VARIANT)"; \
		echo "image:    $(IMAGE)"; \
		echo "machine:  $(MACHINE)"; \
		echo "config:   $(KAS_CONFIG)"; \
		echo "branch:   $$GIT_BRANCH"; \
		echo "commit:   $${GIT_SHA}$${GIT_DIRTY}"; \
		echo "date:     $$(date -Iseconds)"; \
		echo ""; \
		for ext in $(ARTIFACT_EXTS); do \
			f="$(ARTIFACTS_DIR)/$(ARTIFACT_PREFIX)$$ext"; \
			[ -f "$$f" ] && shasum -a 256 "$$f"; \
		done; \
	} > "$$INFO"; \
	echo ""; cat "$$INFO"; echo ""

build-all: ## Build all variants sequentially
	@for v in $(VARIANTS); do \
		echo "=== Building variant: $$v ==="; \
		$(MAKE) VARIANT=$$v build || exit 1; \
	done

# --- Release build matrix ----------------------------------------------------
# Builds all containers and all variants, captures logs per job, and prints a
# summary table at the end.  Each job's output goes to logs/<job>.log so
# failures can be inspected without scrolling.
#
# Container app versions are extracted from ARG *VERSION= or *REF= lines in
# each Dockerfile.  Rootfs version comes from git describe.

RELEASE_LOG_DIR := $(CURDIR)/logs

# Extract the app version from a container's Dockerfile.
# Finds the first ARG whose name ends in _VERSION or _REF.
_container_version = $(shell awk -F= '/^ARG .+_(VERSION|REF)=/{print $$2; exit}' containers/$(1)/Dockerfile 2>/dev/null || echo "latest")

release: ## Build all containers and variants with summary
	@mkdir -p "$(RELEASE_LOG_DIR)" "$(ARTIFACTS_DIR)"
	@GIT_SHA=$$(git -C "$(CURDIR)" rev-parse --short HEAD 2>/dev/null || echo "unknown"); \
	GIT_DIRTY=$$(git -C "$(CURDIR)" diff --quiet 2>/dev/null && echo "" || echo "-dirty"); \
	GIT_DESC=$$(git -C "$(CURDIR)" describe --tags --long --always --dirty 2>/dev/null | sed 's/^v//' || echo "$$GIT_SHA$$GIT_DIRTY"); \
	START=$$(date +%s); \
	TOTAL=0; PASSED=0; FAILED=0; \
	CLR="\033[2K\r"; \
	echo ""; \
	echo "release $$GIT_DESC"; \
	echo ""; \
	LOG="$(RELEASE_LOG_DIR)/build-image.log"; \
	printf "  %-40s %-10s ..." "build-image" "setup"; \
	if $(MAKE) --no-print-directory build-image > "$$LOG" 2>&1; then \
		printf "$$CLR  %-40s %-10s ✓\n" "build-image" "setup"; \
	else \
		printf "$$CLR  %-40s %-10s ✗  -> %s\n" "build-image" "setup" "$$LOG"; \
		echo ""; echo "build-image failed; cannot continue."; \
		cat "$$LOG"; \
		exit 1; \
	fi; \
	for c in $(CONTAINER_NAMES); do \
		TOTAL=$$((TOTAL + 1)); \
		APP_VER=$$(awk -F= '/^ARG .+_(VERSION|REF)=/{print $$2; exit}' "containers/$$c/Dockerfile" 2>/dev/null); \
		[ -z "$$APP_VER" ] && APP_VER="latest"; \
		VER_LABEL="$$APP_VER ($$GIT_SHA$$GIT_DIRTY)"; \
		LOG="$(RELEASE_LOG_DIR)/container-$$c.log"; \
		IMG_TAG="appliance-$$c:latest"; \
		printf "  %-40s container  ..." "$$IMG_TAG"; \
		if $(MAKE) --no-print-directory save-container-$$c > "$$LOG" 2>&1; then \
			PASSED=$$((PASSED + 1)); \
			SIZE=$$(du -h "$(ARTIFACTS_DIR)/appliance-$$c-latest.tar" 2>/dev/null | cut -f1 | tr -d ' '); \
			printf "$$CLR  %-40s container  ✓  %-20s  %s\n" "$$IMG_TAG" "$$VER_LABEL" "$$SIZE"; \
		else \
			FAILED=$$((FAILED + 1)); \
			printf "$$CLR  %-40s container  ✗  %-20s  -> %s\n" "$$IMG_TAG" "$$VER_LABEL" "$$LOG"; \
		fi; \
	done; \
	echo ""; \
	for v in $(VARIANTS); do \
		for phase in firmware update; do \
			TOTAL=$$((TOTAL + 1)); \
			LOG="$(RELEASE_LOG_DIR)/$$v-$$phase.log"; \
			printf "  %-40s %-10s ..." "$$v" "$$phase"; \
			if [ "$$phase" = "firmware" ]; then \
				TARGET="build-firmware"; \
			else \
				TARGET="build-update"; \
			fi; \
			if $(MAKE) --no-print-directory VARIANT=$$v $$TARGET > "$$LOG" 2>&1; then \
				PASSED=$$((PASSED + 1)); \
				V_MACHINE=$$(awk '/^machine:/ {print $$2}' kas/variant-$$v.yaml); \
				V_IMAGE=$$(awk '/^target:/ {print $$2}' kas/variant-$$v.yaml kas/common.yaml | head -1); \
				if [ "$$phase" = "firmware" ]; then \
					ART="$(ARTIFACTS_DIR)/$$v-$$V_IMAGE-$$V_MACHINE.wic.bz2"; \
					[ -f "$$ART" ] || ART="$(ARTIFACTS_DIR)/$$v-$$V_IMAGE-$$V_MACHINE.wic"; \
				else \
					ART="$(ARTIFACTS_DIR)/$$v-$$V_IMAGE-$$V_MACHINE.raucb"; \
				fi; \
				SIZE=$$(du -h "$$ART" 2>/dev/null | cut -f1 | tr -d ' '); \
				printf "$$CLR  %-40s %-10s ✓  %-20s  %s\n" "$$v" "$$phase" "$$GIT_DESC" "$$SIZE"; \
			else \
				FAILED=$$((FAILED + 1)); \
				printf "$$CLR  %-40s %-10s ✗  %-20s  -> %s\n" "$$v" "$$phase" "$$GIT_DESC" "$$LOG"; \
			fi; \
		done; \
	done; \
	END=$$(date +%s); \
	ELAPSED=$$((END - START)); \
	MINS=$$((ELAPSED / 60)); \
	SECS=$$((ELAPSED % 60)); \
	echo ""; \
	echo "$$PASSED/$$TOTAL passed, $$FAILED failed  ($${MINS}m$${SECS}s)"; \
	echo "artifacts: $(ARTIFACTS_DIR)/"; \
	echo "logs:      $(RELEASE_LOG_DIR)/"; \
	echo ""; \
	[ "$$FAILED" -eq 0 ]

status: ## Show bitbake progress from running build containers
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

# --- rpiboot ---
USBBOOT_REPO   := https://github.com/raspberrypi/usbboot
USBBOOT_COMMIT := 42ca50932f67f4571951a11da3c3161561cb49c2
USBBOOT_DIR    := build/usbboot
RPIBOOT        := $(USBBOOT_DIR)/rpiboot

$(USBBOOT_DIR)/.git:
	git clone --recurse-submodules --shallow-submodules \
		$(USBBOOT_REPO) $(USBBOOT_DIR)
	cd $(USBBOOT_DIR) && git checkout $(USBBOOT_COMMIT) && git submodule update --recursive

$(RPIBOOT): $(USBBOOT_DIR)/.git
	@command -v pkg-config >/dev/null || { echo "ERROR: pkg-config not found. Run: brew install pkg-config"; exit 1; }
	@pkg-config --exists libusb-1.0 || { echo "ERROR: libusb not found. Run: brew install libusb"; exit 1; }
	$(MAKE) -C $(USBBOOT_DIR)

rpiboot: $(RPIBOOT) ## Put the CM4 eMMC into USB mass storage mode via rpiboot
	sudo $(RPIBOOT) -d $(USBBOOT_DIR)/mass-storage-gadget64

# --- Remote deploy (x-rebuild-redeploy-<variant>) ----------------------------
# One-command rebuild + deploy to a device over SSH.
#   make DEVICE_IP=192.168.86.99 x-rebuild-redeploy-mycroft-mkii-rpi-devkit-tv
#
# Builds the RAUC update bundle and the variant's app container, transfers
# both to the device, installs the bundle via rauc, and loads the container
# into podman.  Collects os-release and container image ID before and after
# so the summary shows what changed.
DEVICE_IP ?=
DEVICE_USER ?= root

# Resolve which container an app recipe maps to.  Greps the variant's kas
# config for IMAGE_INSTALL entries that match a known container name.
_variant_container = $(strip $(foreach c,$(CONTAINER_NAMES),$(if $(shell grep -q '$(c)' kas/variant-$(1).yaml && echo y),$(c))))

define DEPLOY_RULES
.PHONY: x-rebuild-redeploy-$(1)
x-rebuild-redeploy-$(1): ## Rebuild + deploy $(1) to DEVICE_IP
	$$(if $$(DEVICE_IP),,@echo "ERROR: DEVICE_IP is required"; exit 1)
	$(eval _CONTAINER := $(call _variant_container,$(1)))
	$(eval _V_MACHINE := $(shell awk '/^machine:/ {print $$2}' kas/variant-$(1).yaml))
	$(eval _V_IMAGE := $(shell awk '/^target:/ {print $$2}' kas/variant-$(1).yaml kas/common.yaml | head -1))
	$(eval _RAUCB := $(ARTIFACTS_DIR)/$(1)-$(_V_IMAGE)-$(_V_MACHINE).raucb)
	$(eval _CONTAINER_TAR := $(ARTIFACTS_DIR)/appliance-$(_CONTAINER)-latest.tar)
	@echo "══════════════════════════════════════════════════════════════"
	@echo "  variant:   $(1)"
	@echo "  machine:   $(_V_MACHINE)"
	@echo "  container: $(_CONTAINER)"
	@echo "  device:    $$(DEVICE_USER)@$$(DEVICE_IP)"
	@echo "══════════════════════════════════════════════════════════════"
	@echo ""
	@echo "--- Collecting pre-deploy state from device ---"
	@ssh $$(DEVICE_USER)@$$(DEVICE_IP) '\
		echo "SLOT_STATUS:"; rauc status 2>/dev/null; \
		echo ""; \
		echo "OS_RELEASE:"; cat /etc/os-release 2>/dev/null; \
		echo ""; \
		echo "CONTAINER_IMAGE:"; podman inspect --format="{{.Id}}" appliance-$(_CONTAINER):latest 2>/dev/null || echo "(none)"; \
		echo "CONTAINER_CREATED:"; podman inspect --format="{{.Created}}" appliance-$(_CONTAINER):latest 2>/dev/null || echo "(none)"; \
		echo "UPTIME:"; uptime \
	' | tee /tmp/_appliance_predeploy_$(1).txt
	@echo ""
	@echo "--- Building RAUC bundle + container ---"
	$$(MAKE) VARIANT=$(1) build-update
	$$(if $(_CONTAINER),$$(MAKE) VARIANT=$(1) build-container-$(_CONTAINER) save-container-$(_CONTAINER))
	@echo ""
	@echo "--- Transferring container image ---"
	$$(if $(_CONTAINER),cat "$(_CONTAINER_TAR)" | ssh $$(DEVICE_USER)@$$(DEVICE_IP) podman load)
	@echo ""
	@echo "--- Transferring and installing RAUC bundle ---"
	scp "$(_RAUCB)" $$(DEVICE_USER)@$$(DEVICE_IP):/tmp/
	ssh $$(DEVICE_USER)@$$(DEVICE_IP) rauc install /tmp/$$(notdir $(_RAUCB))
	@echo ""
	@echo "--- Collecting post-deploy state ---"
	@ssh $$(DEVICE_USER)@$$(DEVICE_IP) '\
		echo "SLOT_STATUS:"; rauc status 2>/dev/null; \
		echo ""; \
		echo "CONTAINER_IMAGE:"; podman inspect --format="{{.Id}}" appliance-$(_CONTAINER):latest 2>/dev/null || echo "(none)"; \
		echo "CONTAINER_CREATED:"; podman inspect --format="{{.Created}}" appliance-$(_CONTAINER):latest 2>/dev/null || echo "(none)" \
	' | tee /tmp/_appliance_postdeploy_$(1).txt
	@echo ""
	@echo "══════════════════════════════════════════════════════════════"
	@echo "  DEPLOY COMPLETE"
	@echo "══════════════════════════════════════════════════════════════"
	@echo "  variant:   $(1)"
	@echo "  device:    $$(DEVICE_USER)@$$(DEVICE_IP)"
	@echo ""
	@echo "  Pre-deploy OS:"
	@grep -E 'VERSION_ID=|BUILD_ID=' /tmp/_appliance_predeploy_$(1).txt 2>/dev/null | sed 's/^/    /' || echo "    (unavailable)"
	@echo ""
	@echo "  Pre-deploy container ($(_CONTAINER)):"
	@awk '/^CONTAINER_IMAGE:/{getline; print "    " $$$$0}' /tmp/_appliance_predeploy_$(1).txt 2>/dev/null || echo "    (unavailable)"
	@echo ""
	@echo "  Post-deploy container ($(_CONTAINER)):"
	@awk '/^CONTAINER_IMAGE:/{getline; print "    " $$$$0}' /tmp/_appliance_postdeploy_$(1).txt 2>/dev/null || echo "    (unavailable)"
	@echo ""
	@echo "  RAUC bundle installed. Reboot device to activate."
	@echo "  Post-reboot OS will reflect the new rootfs."
	@echo "══════════════════════════════════════════════════════════════"
	@rm -f /tmp/_appliance_predeploy_$(1).txt /tmp/_appliance_postdeploy_$(1).txt
endef

$(foreach v,$(VARIANTS),$(eval $(call DEPLOY_RULES,$(v))))

clean-cache: ## Reset build state (build volume + sstate) for current VARIANT
	$(CONTAINER_ENGINE) volume rm $(BUILD_VOL) || :
	rm -rf "$(SSTATE_DIR)" || :

clean-cache-all: ## Reset build state (build volumes + sstate) for all variants
	@for v in $(VARIANTS); do \
		$(CONTAINER_ENGINE) volume rm "appliance-$$v-build" || :; \
	done
	rm -rf "$(SSTATE_DIR)" || :

clean: clean-cache-all ## Remove container image, build volumes, and all caches
	$(CONTAINER_ENGINE) rmi $(IMAGE_NAME) || :
	rm -rf "$(CACHE_DIR)" "$(ARTIFACTS_DIR)" build/repos build/usbboot || :
