# Jellyfin Desktop container for appliance-os
#
# Stage 1 rebuilds upstream's Fedora toolchain image and calls
# container-build.sh to compile, assemble, and strip the AppDir.
# Stage 2 copies the AppDir into a minimal Ubuntu 24.04 runtime.
#
# Build (arm64, native only - no cross-compile):
#   podman build --platform linux/arm64 -t appliance-jellyfin-desktop:latest .

# ---------------------------------------------------------------------------
# Stage 1: Fedora toolchain + upstream container-build.sh
# ---------------------------------------------------------------------------

FROM docker.io/library/fedora:latest AS builder

# RPM Fusion provides full FFmpeg (all decoders). Separate layer because
# the RPM Fusion URL embeds the Fedora version and changes on upgrades.
RUN dnf -y upgrade && \
    dnf -y install \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

# Dev toolchain. This is the heaviest layer (~1.5GB) but changes least often.
RUN dnf -y install --allowerasing \
        gcc gcc-c++ make cmake git ninja-build meson python3 pkgconf-pkg-config \
        cargo rust \
        clang-devel \
        glibc-devel \
        alsa-lib-devel at-spi2-core-devel at-spi2-atk-devel atk-devel cairo-devel cups-devel \
        libXcomposite-devel libXdamage-devel libxkbcommon-devel \
        libxkbcommon-x11-devel libXrandr-devel nss-devel nspr-devel pango-devel \
        ffmpeg-devel libplacebo-devel libass-devel wayland-devel \
        libXpresent-devel libXScrnSaver-devel \
        vulkan-headers vulkan-loader-devel wayland-protocols-devel python3-docutils \
        libglvnd-devel mesa-libGL-devel mesa-libEGL-devel mesa-libgbm-devel \
        systemd-devel libdrm-devel libX11-devel xcb-util-cursor-devel \
        pipewire-devel luajit-devel rubberband-devel uchardet-devel \
        xcb-util-devel \
        plasma-wayland-protocols-devel \
        wget file patchelf desktop-file-utils && \
    dnf clean all

# appimagetool + AppImage type2 runtime (arch-independent setup, rarely changes)
WORKDIR /opt/tools
RUN ARCH="$(uname -m)" && \
    wget -q "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${ARCH}.AppImage" && \
    chmod +x "appimagetool-${ARCH}.AppImage" && \
    "./appimagetool-${ARCH}.AppImage" --appimage-extract && \
    mv squashfs-root appimagetool && rm "appimagetool-${ARCH}.AppImage" && \
    wget -q -O "/opt/tools/runtime-${ARCH}" \
        "https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-${ARCH}"

# Clone source. JELLYFIN_DESKTOP_REF controls the checkout: a commit SHA,
# tag, or branch. Defaults to HEAD of main. Pin to a specific ref at a
# higher level (Makefile, CI, version manifest) to get reproducible builds.
ARG JELLYFIN_DESKTOP_REPO=https://github.com/jellyfin/jellyfin-desktop.git
ARG JELLYFIN_DESKTOP_REF=main
RUN git clone --recurse-submodules ${JELLYFIN_DESKTOP_REPO} /src && \
    cd /src && git checkout ${JELLYFIN_DESKTOP_REF}

# Download CEF (separate layer, ~300MB, only changes when upstream bumps CEF version)
WORKDIR /src
RUN cargo xtask fetch-cef

# Build + assemble AppDir via upstream's container-build.sh.
# It handles: cargo build, strip, AppDir layout, lib flattening, LLVM/GPU
# lib stripping, patchelf fixups, and appimagetool packaging.
# /tmp/AppDir survives after the script finishes.
RUN mkdir -p /build /host-output && \
    VERSION=dev /src/dev/linux/appimage/container-build.sh

# On Fedora aarch64, the dynamic linker lives in /usr/lib/ (ABI requirement),
# not /usr/lib64/. container-build.sh copies /usr/lib64 but misses /usr/lib/
# ld-linux-aarch64.so.1. Copy it explicitly if absent.
RUN ARCH="$(uname -m)" && \
    case "$ARCH" in \
        x86_64)  LD_SONAME=ld-linux-x86-64.so.2 ;; \
        aarch64) LD_SONAME=ld-linux-aarch64.so.1 ;; \
    esac && \
    if [ ! -e "/tmp/AppDir/usr/lib/${LD_SONAME}" ]; then \
        cp -L "/lib/${LD_SONAME}" "/tmp/AppDir/usr/lib/${LD_SONAME}"; \
    fi

# ---------------------------------------------------------------------------
# Stage 2: minimal runtime image
# ---------------------------------------------------------------------------
# TODO: use distroless if we dont need any debug tooling inside runtime image
FROM docker.io/library/ubuntu:24.04

# fontconfig: provides /etc/fonts/fonts.conf so CEF and libass can find fonts.
# fonts-dejavu-core: minimal Latin/Cyrillic font set for UI rendering.
RUN apt-get update && \
    apt-get install -y --no-install-recommends fontconfig fonts-dejavu-core && \
    fc-cache -f && \
    rm -rf /var/lib/apt/lists/*

# Copy the assembled AppDir directly (skip AppImage packaging + re-extraction)
COPY --from=builder /tmp/AppDir /opt/jellyfin-desktop

# Install the wrapper script
COPY jellyfin-desktop-wrapper /opt/jellyfin-desktop/jellyfin-desktop-wrapper
RUN chmod +x /opt/jellyfin-desktop/jellyfin-desktop-wrapper

# Verify the bundled linker + libs resolve everything. Uses the same
# interpreter and LD_LIBRARY_PATH that AppRun sets at runtime. If any
# "not found" appears, the build fails here instead of at first boot.
COPY verify-deps.sh /tmp/verify-deps.sh
RUN chmod +x /tmp/verify-deps.sh && /tmp/verify-deps.sh && rm /tmp/verify-deps.sh

# Run as the kiosk user (UID mapped to host via --userns keep-id)
USER 810:810

ENTRYPOINT ["/opt/jellyfin-desktop/jellyfin-desktop-wrapper"]
