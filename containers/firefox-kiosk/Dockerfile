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
        # Wayland client libs (no EGL/GL/GBM -- those come from host gpu-libs)
        libwayland-client0 libwayland-cursor0 libwayland-egl1 \
        libxkbcommon0 \
        # GTK3 (Firefox links against system GTK)
        libgtk-3-0t64 libdbus-1-3 \
        # Audio (PipeWire client)
        libpipewire-0.3-0t64 pipewire-alsa \
        # Fonts
        fonts-dejavu-core fonts-liberation && \
    # Remove Mesa/GL libs that came in as transitive deps.
    # All GPU userspace comes from the host via /usr/lib/gpu bind-mount.
    apt-get purge -y \
        libegl1 libgl1 libgles2 libglvnd0 libgbm1 libdrm2 \
        libegl-mesa0 libgl1-mesa-dri libglx-mesa0 libglx0 \
        mesa-va-drivers mesa-vulkan-drivers 2>/dev/null || true && \
    apt-get purge -y curl gnupg && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# Fail the build if any Mesa/GL/DRM shared objects survived the purge.
# GPU userspace must come exclusively from the host gpu-libs bind-mount.
RUN STRAY=$(find /usr/lib/ -name 'libEGL.so*' -o -name 'libGL.so*' \
        -o -name 'libGLESv2.so*' -o -name 'libgbm.so*' \
        -o -name 'libdrm.so*' -o -name 'libglapi.so*' \
        -o -name '*_dri.so' 2>/dev/null) && \
    if [ -n "$STRAY" ]; then \
        echo "ERROR: GPU libs found in container image. These must come from the host:" && \
        echo "$STRAY" && \
        exit 1; \
    fi

COPY firefox-kiosk-wrapper /usr/local/bin/firefox-kiosk-wrapper
RUN chmod +x /usr/local/bin/firefox-kiosk-wrapper

# Enterprise policies: suppress all first-run prompts, telemetry, update
# checks, and other nags. Locked via policies.json so users can't override.
COPY policies.json /usr/lib/firefox/distribution/policies.json

# Run as the kiosk user (UID mapped to host via --userns keep-id)
USER 810:810

ENTRYPOINT ["/usr/local/bin/firefox-kiosk-wrapper"]
