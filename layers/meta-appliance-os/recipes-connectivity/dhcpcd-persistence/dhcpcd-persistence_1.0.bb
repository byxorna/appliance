SUMMARY = "Persistent dhcpcd lease storage via bind mount"
DESCRIPTION = "Bind-mounts /data/platform/dhcpcd onto /var/lib/dhcpcd so DHCP \
leases survive reboots on a read-only rootfs."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

SRC_URI = " \
    file://dhcpcd-persistence-setup.service \
    file://var-lib-dhcpcd.mount \
"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${S}/dhcpcd-persistence-setup.service ${D}${systemd_system_unitdir}/
    install -m 0644 ${S}/var-lib-dhcpcd.mount ${D}${systemd_system_unitdir}/
}

SYSTEMD_SERVICE:${PN} = "dhcpcd-persistence-setup.service var-lib-dhcpcd.mount"

RDEPENDS:${PN} = "dhcpcd"
