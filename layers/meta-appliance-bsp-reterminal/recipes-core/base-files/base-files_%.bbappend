FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# /root lives on the read-only rootfs. Symlink it to the writable /home
# partition so root's shell history, dotfiles, etc. persist across reboots.
do_install:append () {
    rmdir ${D}/root || rm -rf ${D}/root
    ln -sf /home/root ${D}/root
}
