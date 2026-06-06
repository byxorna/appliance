FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://var-volatile-tmp.conf"

# /root lives on the read-only rootfs. Symlink it to the writable /home
# partition so root's shell history, dotfiles, etc. persist across reboots.
do_install:append () {
    rmdir ${D}/root || rm -rf ${D}/root
    ln -sf /home/root ${D}/root

    install -d -m 0700 ${D}/home/root
    chown root:root ${D}/home/root

    # Ensure /var/volatile/tmp exists early in boot so /var/tmp (a symlink
    # to volatile/tmp) resolves. Required for PrivateTmp=yes services.
    install -d ${D}${prefix}/lib/tmpfiles.d
    install -m 0644 ${WORKDIR}/var-volatile-tmp.conf \
        ${D}${prefix}/lib/tmpfiles.d/var-volatile-tmp.conf
}

FILES:${PN} += "${prefix}/lib/tmpfiles.d/var-volatile-tmp.conf"
