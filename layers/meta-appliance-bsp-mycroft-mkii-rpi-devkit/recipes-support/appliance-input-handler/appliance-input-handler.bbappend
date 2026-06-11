FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://sj201-buttons.conf"

do_install:append() {
    install -d ${D}${sysconfdir}/triggerhappy/triggers.d
    install -m 0644 ${WORKDIR}/sj201-buttons.conf \
        ${D}${sysconfdir}/triggerhappy/triggers.d/sj201-buttons.conf
}

FILES:${PN} += "${sysconfdir}/triggerhappy/triggers.d/sj201-buttons.conf"
