SUMMARY = "Appliance input handler (hardware button to PipeWire/D-Bus dispatcher)"
DESCRIPTION = "Configures triggerhappy to map hardware buttons (volume, media, \
mic mute) to PipeWire volume control and D-Bus MPRIS commands. BSP layers \
provide trigger config files that map device-specific key codes to the \
generic helper scripts installed here."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://volume-up \
    file://volume-down \
    file://media-play-pause \
    file://mic-mute-toggle \
    file://triggerhappy-override.conf \
    file://10-appliance.conf \
"

S = "${WORKDIR}"

RDEPENDS:${PN} = "triggerhappy wireplumber"

inherit useradd

USERADD_PACKAGES = "${PN}"
GROUPADD_PARAM:${PN} = "-g 820 inputd"
USERADD_PARAM:${PN} = "-u 820 -g inputd -r -d / -s /usr/sbin/nologin inputd"

do_install() {
    install -d ${D}${libexecdir}/appliance
    install -m 0755 ${S}/volume-up ${D}${libexecdir}/appliance/volume-up
    install -m 0755 ${S}/volume-down ${D}${libexecdir}/appliance/volume-down
    install -m 0755 ${S}/media-play-pause ${D}${libexecdir}/appliance/media-play-pause
    install -m 0755 ${S}/mic-mute-toggle ${D}${libexecdir}/appliance/mic-mute-toggle

    install -d ${D}${sysconfdir}/triggerhappy/triggers.d

    install -d ${D}${systemd_system_unitdir}/triggerhappy.service.d
    install -m 0644 ${S}/triggerhappy-override.conf \
        ${D}${systemd_system_unitdir}/triggerhappy.service.d/override.conf

    # D-Bus session policy: allow inputd to connect to kiosk's session bus
    # for MPRIS play/pause control
    install -d ${D}${sysconfdir}/dbus-1/session.d
    install -m 0644 ${S}/10-appliance.conf \
        ${D}${sysconfdir}/dbus-1/session.d/10-appliance.conf
}

FILES:${PN} = " \
    ${libexecdir}/appliance/ \
    ${sysconfdir}/triggerhappy/triggers.d/ \
    ${systemd_system_unitdir}/triggerhappy.service.d/ \
    ${sysconfdir}/dbus-1/session.d/ \
"
