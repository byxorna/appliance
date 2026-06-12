SUMMARY = "Jellyfin Desktop media player (containerized)"
DESCRIPTION = "Jellyfin Desktop is a native Jellyfin client using CEF and mpv. \
This recipe ships the host-side systemd units and persistent data plumbing. \
The app itself runs inside an OCI container managed by podman."
HOMEPAGE = "https://github.com/jellyfin/jellyfin-desktop"

LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-3.0-only;md5=c79ff39f19dfec6d293b95dea7b07891"

inherit appliance-app

SRC_URI = " \
    file://app.json \
    file://jellyfin-desktop-config.conf \
    file://home-kiosk-.config-jellyfin-desktop.mount \
    file://home-kiosk-.cache-jellyfin-desktop.mount \
"

# Container image is arm64 only.
COMPATIBLE_HOST = "aarch64.*-linux"

do_install() {
    # Persistent config: tmpfiles.d creates the mount point, systemd .mount
    # unit bind-mounts /data/apps/jellyfin-desktop/ over it.
    install -d ${D}${nonarch_libdir}/tmpfiles.d
    install -m 0644 ${WORKDIR}/jellyfin-desktop-config.conf \
        ${D}${nonarch_libdir}/tmpfiles.d/jellyfin-desktop-config.conf

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/home-kiosk-.config-jellyfin-desktop.mount \
        ${D}${systemd_system_unitdir}/home-kiosk-.config-jellyfin-desktop.mount
    install -m 0644 ${WORKDIR}/home-kiosk-.cache-jellyfin-desktop.mount \
        ${D}${systemd_system_unitdir}/home-kiosk-.cache-jellyfin-desktop.mount
}

SYSTEMD_SERVICE:${PN}:append = " home-kiosk-.config-jellyfin-desktop.mount home-kiosk-.cache-jellyfin-desktop.mount"

FILES:${PN} += " \
    ${nonarch_libdir}/tmpfiles.d/jellyfin-desktop-config.conf \
    ${systemd_system_unitdir}/home-kiosk-.config-jellyfin-desktop.mount \
    ${systemd_system_unitdir}/home-kiosk-.cache-jellyfin-desktop.mount \
"
