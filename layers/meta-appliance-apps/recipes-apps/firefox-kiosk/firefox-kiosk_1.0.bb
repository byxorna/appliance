SUMMARY = "Firefox kiosk browser (containerized)"
DESCRIPTION = "Runs Firefox in kiosk mode inside an OCI container on Weston. \
This recipe ships the host-side systemd units and persistent data plumbing. \
Firefox itself lives entirely in the container image."
HOMEPAGE = "https://www.mozilla.org/firefox/"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit appliance-app

SRC_URI = " \
    file://app.json \
    file://firefox-kiosk-config.conf \
    file://home-kiosk-.mozilla-firefox-kiosk.mount \
    file://home-kiosk-.cache-mozilla-firefox.mount \
    file://home-kiosk-Downloads.mount \
"

# Container image is arm64 only.
COMPATIBLE_HOST = "aarch64.*-linux"

do_install() {
    # Persistent data: tmpfiles.d creates mount points, systemd .mount
    # units bind-mount /data/apps/firefox-kiosk/ subdirs over them.
    install -d ${D}${nonarch_libdir}/tmpfiles.d
    install -m 0644 ${WORKDIR}/firefox-kiosk-config.conf \
        ${D}${nonarch_libdir}/tmpfiles.d/firefox-kiosk-config.conf

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/home-kiosk-.mozilla-firefox-kiosk.mount \
        ${D}${systemd_system_unitdir}/home-kiosk-.mozilla-firefox-kiosk.mount
    install -m 0644 ${WORKDIR}/home-kiosk-.cache-mozilla-firefox.mount \
        ${D}${systemd_system_unitdir}/home-kiosk-.cache-mozilla-firefox.mount
    install -m 0644 ${WORKDIR}/home-kiosk-Downloads.mount \
        ${D}${systemd_system_unitdir}/home-kiosk-Downloads.mount
}

SYSTEMD_SERVICE:${PN}:append = " \
    home-kiosk-.mozilla-firefox-kiosk.mount \
    home-kiosk-.cache-mozilla-firefox.mount \
    home-kiosk-Downloads.mount \
"

FILES:${PN} += " \
    ${nonarch_libdir}/tmpfiles.d/firefox-kiosk-config.conf \
    ${systemd_system_unitdir}/home-kiosk-.mozilla-firefox-kiosk.mount \
    ${systemd_system_unitdir}/home-kiosk-.cache-mozilla-firefox.mount \
    ${systemd_system_unitdir}/home-kiosk-Downloads.mount \
"
