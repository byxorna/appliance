# Jellyfin Desktop container for appliance-os
#
# Multi-stage build: stage 1 compiles jellyfin-desktop from source on
# Fedora (matching upstream's AppImage toolchain), stage 2 copies the
# assembled AppDir into a minimal Ubuntu 24.04 runtime image.
#
# Build (arm64, native only - no cross-compile):
#   podman build --platform linux/arm64 -t appliance-jellyfin-desktop:latest .
#
# The container expects these host-side bind mounts (provided by the
# appliance-app systemd service unit):
#   - Wayland socket:  /run/user/810/wayland-<vt>
#   - PipeWire socket: /run/user/810/pipewire-0
#   - D-Bus sockets:   /run/dbus/system_bus_socket, /run/user/810/bus
#   - GPU device:      /dev/dri
#   - Persistent data: /data/apps/jellyfin-desktop/

# ---------------------------------------------------------------------------
# Stage 1: build jellyfin-desktop from source
# ---------------------------------------------------------------------------
# Layers are ordered slowest-changing first for optimal cache reuse:
#   1. OS + RPM Fusion repos (changes ~yearly)
#   2. Dev toolchain packages (changes rarely)
#   3. appimagetool + runtime (changes rarely)
#   4. Source clone at pinned commit (changes per update)
#   5. CEF download (changes when upstream bumps CEF)
#   6. Cargo build + AppDir assembly (changes per update)

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

# Build jellyfin-desktop + mpv from source
RUN cargo xtask build --out /build

# Assemble AppDir (reproduces container-build.sh logic)
RUN set -eu && \
    ARCH="$(uname -m)" && \
    case "$ARCH" in \
        x86_64)  LD_SONAME=ld-linux-x86-64.so.2 ;; \
        aarch64) LD_SONAME=ld-linux-aarch64.so.1 ;; \
        *) echo "unsupported arch: $ARCH" >&2; exit 1 ;; \
    esac && \
    strip /build/*.so /build/jellyfin-desktop && \
    APPDIR=/tmp/AppDir && \
    rm -rf "$APPDIR" && \
    mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share" && \
    cp /build/jellyfin-desktop "$APPDIR/usr/bin/" && \
    cp /build/*.pak "$APPDIR/usr/bin/" && \
    cp /build/icudtl.dat "$APPDIR/usr/bin/" && \
    cp /build/v8_context_snapshot.bin "$APPDIR/usr/bin/" && \
    cp -r /build/locales "$APPDIR/usr/bin/" && \
    cp /build/vk_swiftshader_icd.json "$APPDIR/usr/bin/" 2>/dev/null || true && \
    cp /build/libcef.so "$APPDIR/usr/bin/" && \
    cp /build/libEGL.so "$APPDIR/usr/bin/" && \
    cp /build/libGLESv2.so "$APPDIR/usr/bin/" && \
    cp /build/libvk_swiftshader.so "$APPDIR/usr/bin/" && \
    cp -a /usr/lib64 "$APPDIR/usr/lib" && \
    cp /build/libmpv.so.2 "$APPDIR/usr/lib/" && \
    mkdir -p "$APPDIR/usr/share/crypto-policies/DEFAULT" && \
    cp /usr/share/crypto-policies/DEFAULT/gnutls.txt \
       "$APPDIR/usr/share/crypto-policies/DEFAULT/gnutls.txt" && \
    mkdir -p "$APPDIR/usr/share/applications" \
             "$APPDIR/usr/share/icons/hicolor/scalable/apps" \
             "$APPDIR/usr/share/metainfo" && \
    cp /src/resources/linux/org.jellyfin.JellyfinDesktop.desktop \
       "$APPDIR/usr/share/applications/" && \
    cp /src/resources/linux/org.jellyfin.JellyfinDesktop.svg \
       "$APPDIR/usr/share/icons/hicolor/scalable/apps/" && \
    cp /src/resources/linux/org.jellyfin.JellyfinDesktop.metainfo.xml \
       "$APPDIR/usr/share/metainfo/" && \
    find "$APPDIR/usr/lib" -name '*.a' -delete && \
    rm -rf "$APPDIR/usr/lib/pkgconfig" \
           "$APPDIR/usr/lib/cmake" \
           "$APPDIR/usr/lib/python"* \
           "$APPDIR/usr/lib/perl"* \
           "$APPDIR/usr/lib/ruby"* \
           "$APPDIR/usr/lib/node_modules" \
           "$APPDIR/usr/lib/gcc" \
           "$APPDIR/usr/lib/bfd-plugins" \
           "$APPDIR/usr/lib/ldscripts" \
           "$APPDIR/usr/lib/systemd" \
           "$APPDIR"/usr/lib/libLLVM* \
           "$APPDIR"/usr/lib/llvm* \
           "$APPDIR"/usr/lib/clang* \
           "$APPDIR"/usr/lib/LLVMgold* \
           "$APPDIR"/usr/lib/libLTO* \
           "$APPDIR"/usr/lib/libgallium* \
           "$APPDIR"/usr/lib/dri_gbm.so* \
           "$APPDIR"/usr/lib/gbm/dri_gbm.so* \
           "$APPDIR"/usr/lib/udev* \
           "$APPDIR"/usr/lib/guile* \
           "$APPDIR"/usr/lib/git* \
           "$APPDIR/usr/share/doc" \
           "$APPDIR/usr/share/man" \
           "$APPDIR/usr/share/info" \
           "$APPDIR/usr/share/gtk-doc" \
           "$APPDIR/usr/share/locale" \
           "$APPDIR/usr/share/i18n" \
           "$APPDIR/usr/share/help" \
           "$APPDIR/usr/share/bash-completion" \
           "$APPDIR/usr/share/zsh" \
           "$APPDIR/usr/share/fish" \
           "$APPDIR/usr/share/vala" && \
    rm -rf "$APPDIR/usr/lib/dri" "$APPDIR/usr/lib/vdpau" && \
    rm -f "$APPDIR"/usr/lib/libEGL.so* \
          "$APPDIR"/usr/lib/libEGL_mesa.so* \
          "$APPDIR"/usr/lib/libGL.so* \
          "$APPDIR"/usr/lib/libGLX.so* \
          "$APPDIR"/usr/lib/libGLX_mesa.so* \
          "$APPDIR"/usr/lib/libGLESv1_CM.so* \
          "$APPDIR"/usr/lib/libGLESv2.so* \
          "$APPDIR"/usr/lib/libGLdispatch.so* \
          "$APPDIR"/usr/lib/libOpenGL.so* \
          "$APPDIR"/usr/lib/libgbm.so* \
          "$APPDIR"/usr/lib/libvulkan.so* \
          "$APPDIR"/usr/lib/libdrm.so* \
          "$APPDIR"/usr/lib/libdrm_*.so* \
          "$APPDIR"/usr/lib/libxshmfence.so* \
          "$APPDIR"/usr/lib/libglapi.so* && \
    find "$APPDIR/usr/lib" -mindepth 2 \( -name '*.so' -o -name '*.so.*' \) | while read lib; do \
        base="$(basename "$lib")" && \
        [ ! -e "$APPDIR/usr/lib/$base" ] && cp -L "$lib" "$APPDIR/usr/lib/$base"; \
    done && \
    find "$APPDIR/usr/lib" "$APPDIR/usr/bin" -type f \( -name '*.so*' -o -executable \) 2>/dev/null | while read f; do \
        patchelf --print-needed "$f" 2>/dev/null | grep '^/' | while read lib; do \
            base="$(basename "$lib")" && \
            patchelf --replace-needed "$lib" "$base" "$f" 2>/dev/null || true; \
        done; \
    done && \
    patchelf --set-interpreter "/tmp/.jf-cef-interp/${LD_SONAME}" \
        "$APPDIR/usr/bin/jellyfin-desktop" && \
    cp "$APPDIR/usr/share/applications/org.jellyfin.JellyfinDesktop.desktop" "$APPDIR/" && \
    cp "$APPDIR/usr/share/icons/hicolor/scalable/apps/org.jellyfin.JellyfinDesktop.svg" "$APPDIR/" && \
    ln -sf org.jellyfin.JellyfinDesktop.svg "$APPDIR/.DirIcon" && \
    cp /src/dev/linux/appimage/AppRun "$APPDIR/AppRun" && \
    chmod +x "$APPDIR/AppRun"

# ---------------------------------------------------------------------------
# Stage 2: minimal runtime image
# ---------------------------------------------------------------------------
FROM docker.io/library/ubuntu:24.04

# Copy the assembled AppDir directly (skip AppImage packaging + re-extraction)
COPY --from=builder /tmp/AppDir /opt/jellyfin-desktop

# Install the wrapper script
COPY jellyfin-desktop-wrapper /opt/jellyfin-desktop/jellyfin-desktop-wrapper
RUN chmod +x /opt/jellyfin-desktop/jellyfin-desktop-wrapper

# Run as the kiosk user (UID mapped to host via --userns keep-id)
USER 810:810

ENTRYPOINT ["/opt/jellyfin-desktop/jellyfin-desktop-wrapper"]
