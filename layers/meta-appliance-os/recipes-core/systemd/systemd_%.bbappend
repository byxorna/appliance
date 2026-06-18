FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " \
    file://logind.conf.d/00-appliance.conf \
    file://sleep.conf.d/00-appliance.conf \
    file://networkd-wait-online.conf \
"

do_install:append() {
    install -d ${D}${sysconfdir}/systemd/logind.conf.d
    install -m 0644 ${WORKDIR}/logind.conf.d/00-appliance.conf \
        ${D}${sysconfdir}/systemd/logind.conf.d/00-appliance.conf

    install -d ${D}${sysconfdir}/systemd/sleep.conf.d
    install -m 0644 ${WORKDIR}/sleep.conf.d/00-appliance.conf \
        ${D}${sysconfdir}/systemd/sleep.conf.d/00-appliance.conf

    install -d ${D}${systemd_system_unitdir}/systemd-networkd-wait-online.service.d
    install -m 0644 ${WORKDIR}/networkd-wait-online.conf \
        ${D}${systemd_system_unitdir}/systemd-networkd-wait-online.service.d/00-any.conf
}

FILES:${PN} += " \
    ${sysconfdir}/systemd/logind.conf.d/ \
    ${sysconfdir}/systemd/sleep.conf.d/ \
    ${systemd_system_unitdir}/systemd-networkd-wait-online.service.d/ \
"
