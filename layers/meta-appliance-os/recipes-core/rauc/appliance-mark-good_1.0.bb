SUMMARY = "Mark RAUC slot as good after successful boot"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://appliance-mark-good.service"

inherit systemd

SYSTEMD_SERVICE:${PN} = "appliance-mark-good.service"

RDEPENDS:${PN} = "rauc"

do_install() {
    install -d ${D}${systemd_unitdir}/system/
    install -m 0644 ${WORKDIR}/appliance-mark-good.service ${D}${systemd_unitdir}/system/
}
