SUMMARY = "Overlayfs mount for /etc backed by /data/platform"
DESCRIPTION = "Mounts an overlayfs on /etc so the read-only rootfs gets a \
persistent writable layer stored in /data/platform/etc-overlay. Changes to \
/etc survive reboots but OTA rootfs updates to /etc files still show through \
unless explicitly overridden in the upper layer."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

SRC_URI = " \
    file://etc-overlay-setup.service \
    file://etc.mount \
"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${S}/etc-overlay-setup.service ${D}${systemd_system_unitdir}/
    install -m 0644 ${S}/etc.mount ${D}${systemd_system_unitdir}/
}

SYSTEMD_SERVICE:${PN} = "etc-overlay-setup.service etc.mount"

RDEPENDS:${PN} = "util-linux-mount"
