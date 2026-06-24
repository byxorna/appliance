SUMMARY = "Ratspeak mesh messenger (containerized)"
DESCRIPTION = "Ratspeak is a Reticulum-based mesh messenger. \
This recipe ships the host-side systemd units and persistent data plumbing. \
The app itself runs inside an OCI container managed by podman."
HOMEPAGE = "https://github.com/ratspeak/Ratspeak"

LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-3.0-only;md5=c79ff39f19dfec6d293b95dea7b07891"

inherit appliance-app

SRC_URI = " \
    file://app.json \
    file://ratspeak-config.conf \
    file://home-kiosk-.local-share-org.ratspeak.desktop.mount \
"

COMPATIBLE_HOST = "aarch64.*-linux"

do_install() {
    install -d ${D}${nonarch_libdir}/tmpfiles.d
    install -m 0644 ${WORKDIR}/ratspeak-config.conf \
        ${D}${nonarch_libdir}/tmpfiles.d/ratspeak-config.conf

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/home-kiosk-.local-share-org.ratspeak.desktop.mount \
        ${D}${systemd_system_unitdir}/home-kiosk-.local-share-org.ratspeak.desktop.mount
}

SYSTEMD_SERVICE:${PN}:append = " home-kiosk-.local-share-org.ratspeak.desktop.mount"

FILES:${PN} += " \
    ${nonarch_libdir}/tmpfiles.d/ratspeak-config.conf \
    ${systemd_system_unitdir}/home-kiosk-.local-share-org.ratspeak.desktop.mount \
"
