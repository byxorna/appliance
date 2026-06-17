# Firefox kiosk browser container for appliance-os
#
# Runs Firefox in kiosk mode on the host's Weston compositor via Wayland
# socket passthrough. Audio via PipeWire. No desktop environment needed.
#
# Build (arm64):
#   podman build --platform linux/arm64 -t appliance-firefox-kiosk:latest .
#
# The container expects these host-side bind mounts (provided by the
# appliance-app systemd service unit):
#   - Wayland socket:  /run/user/810/wayland-<vt>
#   - PipeWire socket: /run/user/810/pipewire-0
#   - D-Bus sockets:   /run/dbus/system_bus_socket, /run/user/810/bus
#   - GPU device:      /dev/dri
#   - Persistent data: /data/apps/firefox-kiosk/

FROM docker.io/library/ubuntu:resolute

# Mozilla's official apt repository for up-to-date Firefox (not snap).
# https://support.mozilla.org/en-US/kb/install-firefox-linux#w_install-firefox-deb-package-for-debian-based-distributions
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg && \
    install -d -m 0755 /etc/apt/keyrings && \
    curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg \
        -o /etc/apt/keyrings/packages.mozilla.org.asc && \
    echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
        > /etc/apt/sources.list.d/mozilla.list && \
    echo 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
        > /etc/apt/preferences.d/mozilla && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        firefox \
        # Wayland + GL
        libwayland-client0 libwayland-cursor0 libwayland-egl1 \
        libxkbcommon0 libdrm2 libgbm1 \
        libegl1 libgl1 libgles2 \
        # GTK3 (Firefox links against system GTK)
        libgtk-3-0t64 libdbus-1-3 \
        # Audio (PipeWire client)
        libpipewire-0.3-0t64 pipewire-alsa \
        # Fonts
        fonts-dejavu-core fonts-liberation && \
    apt-get purge -y curl gnupg && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

COPY firefox-kiosk-wrapper /usr/local/bin/firefox-kiosk-wrapper
RUN chmod +x /usr/local/bin/firefox-kiosk-wrapper

# Run as the kiosk user (UID mapped to host via --userns keep-id)
USER 810:810

ENTRYPOINT ["/usr/local/bin/firefox-kiosk-wrapper"]
