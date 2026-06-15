SUMMARY = "Persistent timesync clock storage via bind mount"
DESCRIPTION = "Bind-mounts /data/platform/timesync onto /var/lib/systemd/timesync \
so the systemd-timesyncd clock file survives reboots on a read-only rootfs."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

SRC_URI = " \
    file://timesync-persistence-setup.service \
    file://var-lib-systemd-timesync.mount \
"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${S}/timesync-persistence-setup.service ${D}${systemd_system_unitdir}/
    install -m 0644 ${S}/var-lib-systemd-timesync.mount ${D}${systemd_system_unitdir}/
}

SYSTEMD_SERVICE:${PN} = "timesync-persistence-setup.service var-lib-systemd-timesync.mount"

RDEPENDS:${PN} = "systemd"
