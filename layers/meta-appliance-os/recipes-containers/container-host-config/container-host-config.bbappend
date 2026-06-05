# Override container configuration for appliance-os.
# The rootfs is read-only, so container images must live on writable storage
# that survives A/B rootfs updates. Temp files for image operations also
# need persistent writable storage (image_copy_tmp_dir in containers.conf).

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://containers.conf"

do_install:append() {
    install ${WORKDIR}/containers.conf ${D}/${sysconfdir}/containers/containers.conf
}
