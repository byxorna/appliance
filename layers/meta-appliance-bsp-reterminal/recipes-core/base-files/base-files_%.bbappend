FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://var-volatile-tmp.conf"

do_install:append () {
    # Ensure /var/volatile/tmp exists early in boot so /var/tmp (a symlink
    # to volatile/tmp) resolves. Required for PrivateTmp=yes services.
    install -d ${D}${prefix}/lib/tmpfiles.d
    install -m 0644 ${WORKDIR}/var-volatile-tmp.conf \
        ${D}${prefix}/lib/tmpfiles.d/var-volatile-tmp.conf
}

FILES:${PN} += "${prefix}/lib/tmpfiles.d/var-volatile-tmp.conf"
