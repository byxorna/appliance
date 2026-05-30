# Pick up our custom weston.ini (kiosk-shell + DSI rotation) and
# weston-autologin (pam_systemd required, not optional) via FILESEXTRAPATHS.
# Both exist in upstream SRC_URI — our versions override by search order.
FILESEXTRAPATHS:prepend := "${THISDIR}/weston-init:"

# weston-homedir.conf is new (not in upstream SRC_URI)
SRC_URI += "file://weston-homedir.conf"

do_install:append() {
    # tmpfiles.d: create /home/weston at boot if missing (the /home
    # partition is separate from rootfs so the recipe's install is hidden)
    install -d ${D}${nonarch_libdir}/tmpfiles.d
    install -m 0644 ${WORKDIR}/weston-homedir.conf ${D}${nonarch_libdir}/tmpfiles.d/
}

FILES:${PN} += "${nonarch_libdir}/tmpfiles.d/weston-homedir.conf"
