# Pick up our custom weston.ini (kiosk-shell + DSI rotation) and
# weston-autologin (pam_systemd required, not optional) via FILESEXTRAPATHS.
# Both exist in upstream SRC_URI — our versions override by search order.
FILESEXTRAPATHS:prepend := "${THISDIR}/weston-init:"

# weston-homedir.conf is new (not in upstream SRC_URI), and so are the
# userdb dropin files for systemd's varlink user database.
SRC_URI += "file://weston-homedir.conf"
SRC_URI += "file://weston.user"
SRC_URI += "file://weston.group"

do_install:append() {
    # tmpfiles.d: create /home/weston at boot if missing (the /home
    # partition is separate from rootfs so the recipe's install is hidden)
    install -d ${D}${nonarch_libdir}/tmpfiles.d
    install -m 0644 ${WORKDIR}/weston-homedir.conf ${D}${nonarch_libdir}/tmpfiles.d/

    # userdb dropin: provide weston's user/group record to systemd-userwork.
    # Works around a systemd 255 bug where add_nss_service() in the worker
    # reads /etc/machine-id (empty on RO rootfs) and returns ENOMEDIUM.
    # The "service" field in the JSON prevents add_nss_service() from running.
    install -d ${D}${nonarch_libdir}/userdb
    install -m 0644 ${WORKDIR}/weston.user ${D}${nonarch_libdir}/userdb/
    install -m 0644 ${WORKDIR}/weston.group ${D}${nonarch_libdir}/userdb/
}

FILES:${PN} += " \
    ${nonarch_libdir}/tmpfiles.d/weston-homedir.conf \
    ${nonarch_libdir}/userdb/weston.user \
    ${nonarch_libdir}/userdb/weston.group \
"
