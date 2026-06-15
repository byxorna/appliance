FILESEXTRAPATHS:prepend := "${THISDIR}/weston-init:"

SRC_URI += "file://drm-device.conf"
SRC_URI += "file://90-drm-systemd.rules"

do_install:append() {
    install -d ${D}${systemd_system_unitdir}/weston@.service.d
    install -m 0644 ${WORKDIR}/drm-device.conf \
        ${D}${systemd_system_unitdir}/weston@.service.d/drm-device.conf

    install -d ${D}${nonarch_base_libdir}/udev/rules.d
    install -m 0644 ${WORKDIR}/90-drm-systemd.rules \
        ${D}${nonarch_base_libdir}/udev/rules.d/90-drm-systemd.rules
}

FILES:${PN} += "\
    ${systemd_system_unitdir}/weston@.service.d/drm-device.conf \
    ${nonarch_base_libdir}/udev/rules.d/90-drm-systemd.rules \
"
