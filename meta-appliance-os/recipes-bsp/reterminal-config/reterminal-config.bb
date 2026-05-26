SUMMARY = "reTerminal hardware configuration"
DESCRIPTION = "Installs modules-load.d config for early DSI panel module load on the Seeed reTerminal."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://reterminal.conf"

S = "${WORKDIR}"

inherit allarch

do_install() {
    install -d ${D}${sysconfdir}/modules-load.d
    install -m 0644 ${S}/reterminal.conf ${D}${sysconfdir}/modules-load.d/reterminal.conf
}

FILES:${PN} = "${sysconfdir}/modules-load.d/reterminal.conf"
