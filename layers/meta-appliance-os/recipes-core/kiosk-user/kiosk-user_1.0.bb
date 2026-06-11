SUMMARY = "Kiosk app user account and runtime directories"
DESCRIPTION = "Creates the unprivileged kiosk user account that runs all \
appliance apps. Provides userdb dropins (for the systemd 255 ENOMEDIUM \
workaround), a tmpfiles.d config for /home/kiosk, the kiosk-session \
systemd unit (which gives kiosk a real systemd --user session via PAM), \
and the static UID/GID assignment."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit useradd systemd

SRC_URI = " \
    file://kiosk.user \
    file://kiosk.group \
    file://kiosk-runtime.conf \
    file://kiosk-session.service \
    file://kiosk-session \
"

S = "${WORKDIR}"

USERADD_PACKAGES = "${PN}"
# useradd-staticids rewrites --user-group to --gid 810 and auto-injects the
# primary kiosk group into GROUPADD_PARAM.  Supplementary groups referenced
# by -G must also exist in the sysroot when useradd runs at
# do_prepare_recipe_sysroot time.  audio/video come from base-passwd (pulled
# in by useradd.bbclass DEPENDS), but wayland may not yet be present since
# weston-init is not a build dependency.  Creating it with -r (system group)
# here is idempotent — groupadd is a no-op if the group already exists.
GROUPADD_PARAM:${PN} = "-r wayland; -r pipewire"
USERADD_PARAM:${PN} = "--user-group --home /home/kiosk --shell /usr/sbin/nologin -G wayland,audio,video,pipewire kiosk"

SYSTEMD_SERVICE:${PN} = "kiosk-session.service"

do_install() {
    # userdb dropins: provide kiosk user/group to systemd-userwork
    # (same pattern as weston-init for the weston user)
    install -d ${D}${nonarch_libdir}/userdb
    install -m 0644 ${S}/kiosk.user ${D}${nonarch_libdir}/userdb/
    install -m 0644 ${S}/kiosk.group ${D}${nonarch_libdir}/userdb/

    # tmpfiles.d: create /home/kiosk at boot
    install -d ${D}${nonarch_libdir}/tmpfiles.d
    install -m 0644 ${S}/kiosk-runtime.conf ${D}${nonarch_libdir}/tmpfiles.d/

    # kiosk-session.service: holds a logind session open for kiosk so
    # systemd --user starts and PipeWire/D-Bus/WirePlumber run as UID 810
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${S}/kiosk-session.service ${D}${systemd_system_unitdir}/

    # PAM config for kiosk-session (triggers pam_systemd to create /run/user/810)
    install -d ${D}${sysconfdir}/pam.d
    install -m 0644 ${S}/kiosk-session ${D}${sysconfdir}/pam.d/
}

FILES:${PN} = " \
    ${nonarch_libdir}/userdb/kiosk.user \
    ${nonarch_libdir}/userdb/kiosk.group \
    ${nonarch_libdir}/tmpfiles.d/kiosk-runtime.conf \
    ${systemd_system_unitdir}/kiosk-session.service \
    ${sysconfdir}/pam.d/kiosk-session \
"
