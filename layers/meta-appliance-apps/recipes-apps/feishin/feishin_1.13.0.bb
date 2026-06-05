SUMMARY = "Feishin music player (containerized)"
DESCRIPTION = "Feishin is a music player frontend for Navidrome and Jellyfin. \
This recipe ships the host-side systemd units and persistent data plumbing. \
The app itself runs inside an OCI container managed by podman."
HOMEPAGE = "https://github.com/jeffvli/feishin"

LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-3.0-only;md5=c79ff39f19dfec6d293b95dea7b07891"

inherit appliance-app

SRC_URI = " \
    file://app.json \
    file://feishin-config.conf \
    file://home-kiosk-.config-feishin.mount \
"

# Container image is arm64 only.
COMPATIBLE_HOST = "aarch64.*-linux"

do_install() {
    # Persistent config: tmpfiles.d creates the mount point, systemd .mount
    # unit bind-mounts /data/apps/feishin/ over it.
    install -d ${D}${nonarch_libdir}/tmpfiles.d
    install -m 0644 ${WORKDIR}/feishin-config.conf \
        ${D}${nonarch_libdir}/tmpfiles.d/feishin-config.conf

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/home-kiosk-.config-feishin.mount \
        ${D}${systemd_system_unitdir}/home-kiosk-.config-feishin.mount
}

SYSTEMD_SERVICE:${PN}:append = " home-kiosk-.config-feishin.mount"

FILES:${PN} += " \
    ${nonarch_libdir}/tmpfiles.d/feishin-config.conf \
    ${systemd_system_unitdir}/home-kiosk-.config-feishin.mount \
"
