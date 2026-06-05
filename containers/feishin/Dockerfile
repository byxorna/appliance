# Feishin music player container for appliance-os
#
# Runs on the host's Weston compositor via Wayland socket passthrough.
# Audio via PipeWire socket passthrough. MPRIS via D-Bus passthrough.
#
# Build (arm64):
#   podman build --platform linux/arm64 -t ghcr.io/byxorna/appliance-feishin:latest .
#
# The container expects these host-side bind mounts (provided by the
# appliance-app systemd service unit):
#   - Wayland socket:  /run/user/810/wayland-<vt>
#   - PipeWire socket: /run/user/810/pipewire-0
#   - D-Bus sockets:   /run/dbus/system_bus_socket, /run/user/810/bus
#   - GPU device:      /dev/dri
#   - Persistent data: /data/apps/feishin/

FROM docker.io/library/ubuntu:24.04

# Libraries that Electron/Chromium needs from the system.
# The AppImage bundles its own Electron but links against system GTK, mesa,
# NSS, etc. Ubuntu 24.04 provides matching versions since the AppImage was
# built on Ubuntu.
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Wayland + GL
    libwayland-client0 libwayland-cursor0 libwayland-egl1 \
    libxkbcommon0 libdrm2 libgbm1 \
    libegl1 libgl1 libgles2 \
    # GTK3 + friends (Electron links against system GTK)
    libgtk-3-0t64 libnss3 libnspr4 \
    libatk1.0-0t64 libatk-bridge2.0-0t64 libatspi2.0-0t64 \
    libpango-1.0-0 libcairo2 \
    libgdk-pixbuf-2.0-0 libglib2.0-0t64 \
    libdbus-1-3 libcups2t64 libexpat1 \
    # Audio (PipeWire client + ALSA compat)
    libasound2t64 \
    libpipewire-0.3-0t64 pipewire-alsa \
    # AppImage extraction
    squashfs-tools file \
    # X11 client libs (Electron links against these even in Wayland mode)
    libx11-6 libxcomposite1 libxdamage1 libxext6 libxfixes3 libxrandr2 \
    libxcb1 \
    && rm -rf /var/lib/apt/lists/*

# Download and extract the Feishin AppImage.
# --appimage-extract works natively here because the container is arm64
# and the AppImage is arm64 — no cross-arch squashfs offset hacks needed.
ARG FEISHIN_VERSION=1.13.0
ADD https://github.com/jeffvli/feishin/releases/download/v${FEISHIN_VERSION}/Feishin-linux-arm64.AppImage /tmp/feishin.AppImage
RUN chmod +x /tmp/feishin.AppImage && \
    cd /tmp && /tmp/feishin.AppImage --appimage-extract && \
    mv /tmp/squashfs-root /opt/feishin && \
    rm /tmp/feishin.AppImage

# Install the wrapper script
COPY feishin-wrapper /opt/feishin/feishin-wrapper
RUN chmod +x /opt/feishin/feishin-wrapper

# Run as the kiosk user (UID mapped to host via --userns keep-id)
USER 810:810

ENTRYPOINT ["/opt/feishin/feishin-wrapper"]
