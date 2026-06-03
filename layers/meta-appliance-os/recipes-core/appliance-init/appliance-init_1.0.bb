SUMMARY = "Appliance OS platform initialization"
DESCRIPTION = "Creates persistent data directories on /data and switches \
the active VT to the default app VT at boot."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

SRC_URI = " \
    file://appliance-init.service \
    file://appliance-default-vt.service \
"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${S}/appliance-init.service ${D}${systemd_system_unitdir}/
    install -m 0644 ${S}/appliance-default-vt.service ${D}${systemd_system_unitdir}/
}

SYSTEMD_SERVICE:${PN} = "appliance-init.service appliance-default-vt.service"

RDEPENDS:${PN} = "kbd"
