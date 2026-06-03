# Pick up our custom weston.ini (kiosk-shell base config, no rotation) and
# weston-autologin (pam_systemd required, not optional) via FILESEXTRAPATHS.
# Both exist in upstream SRC_URI — our versions override by search order.
# Display rotation is hardware-specific and belongs in BSP layer bbappends.
FILESEXTRAPATHS:prepend := "${THISDIR}/weston-init:"

# weston-homedir.conf is new (not in upstream SRC_URI), and so are the
# userdb dropin files for systemd's varlink user database.
SRC_URI += "file://weston-homedir.conf"
SRC_URI += "file://weston.user"
SRC_URI += "file://weston.group"
SRC_URI += "file://weston@.service"

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

    # Per-VT template unit: allows weston@2.service, weston@7.service, etc.
    install -m 0644 ${WORKDIR}/weston@.service ${D}${systemd_system_unitdir}/weston@.service

    # Disable the upstream singleton weston.service — we use weston@.service
    # template instances instead.  Don't delete it (other recipes may RDEPEND
    # on weston-init and expect the file to parse), just mask it so it never
    # starts.
    ln -sf /dev/null ${D}${systemd_system_unitdir}/weston.service

    # Enable weston@2 (the default app VT) at boot.
    # Additional VTs are enabled by app recipes via their own .wants symlinks.
    install -d ${D}${systemd_system_unitdir}/graphical.target.wants
    ln -sf ../weston@.service ${D}${systemd_system_unitdir}/graphical.target.wants/weston@2.service
}

FILES:${PN} += " \
    ${nonarch_libdir}/tmpfiles.d/weston-homedir.conf \
    ${nonarch_libdir}/userdb/weston.user \
    ${nonarch_libdir}/userdb/weston.group \
    ${systemd_system_unitdir}/weston@.service \
    ${systemd_system_unitdir}/graphical.target.wants/weston@2.service \
"

# Tell the systemd class about the template unit.  The upstream recipe
# declares SYSTEMD_SERVICE = "weston.service weston.socket" — we keep the
# socket (harmless) and add our template.  Masking the singleton above
# prevents it from starting even though it's still listed.
SYSTEMD_SERVICE:${PN} += "weston@.service"
