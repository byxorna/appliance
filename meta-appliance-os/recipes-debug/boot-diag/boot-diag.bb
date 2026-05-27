SUMMARY = "First-boot diagnostic dump to /boot partition"
DESCRIPTION = "Writes SSH, network, and systemd status to /boot/boot-diag.log \
so it can be read via rpiboot when SSH is not working."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://boot-diag.sh \
    file://boot-diag.service \
"


inherit systemd

SYSTEMD_SERVICE:${PN} = "boot-diag.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${libexecdir}
    install -m 0755 ${WORKDIR}/boot-diag.sh ${D}${libexecdir}/boot-diag.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/boot-diag.service ${D}${systemd_system_unitdir}/boot-diag.service
}

FILES:${PN} = " \
    ${libexecdir}/boot-diag.sh \
    ${systemd_system_unitdir}/boot-diag.service \
"
