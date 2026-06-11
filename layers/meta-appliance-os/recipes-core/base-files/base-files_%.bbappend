FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# /root lives on the read-only rootfs. Symlink it to the writable /home
# partition so root's shell history, dotfiles, etc. persist across reboots.
# This is appliance-wide policy (read-only rootfs + persistent /home), not
# hardware-specific, so it belongs in the distro layer rather than a BSP.
SRC_URI += "file://zshrc"

do_install:append () {
    rmdir ${D}/root || rm -rf ${D}/root
    ln -sf /home/root ${D}/root

    install -d -m 0700 ${D}/home/root
    install -m 0644 ${WORKDIR}/zshrc ${D}/home/root/.zshrc
    chown root:root ${D}/home/root ${D}/home/root/.zshrc
}
