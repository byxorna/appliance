SUMMARY = "Self-update script that builds a RAUC bundle from source"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://appliance-selfupdate"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${S}/appliance-selfupdate ${D}${bindir}/
}

RDEPENDS:${PN} = "git make"
