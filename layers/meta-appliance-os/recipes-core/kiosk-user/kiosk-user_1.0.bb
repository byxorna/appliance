SUMMARY = "Kiosk app user account and runtime directories"
DESCRIPTION = "Creates the unprivileged kiosk user account that runs all \
appliance apps. Provides userdb dropins (for the systemd 255 ENOMEDIUM \
workaround), a tmpfiles.d config for /home/kiosk and /run/user/810, \
and the static UID/GID assignment."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit useradd

SRC_URI = " \
    file://kiosk.user \
    file://kiosk.group \
    file://kiosk-runtime.conf \
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
GROUPADD_PARAM:${PN} = "-r wayland"
USERADD_PARAM:${PN} = "--user-group --home /home/kiosk --shell /usr/sbin/nologin -G wayland,audio,video kiosk"

do_install() {
    # userdb dropins: provide kiosk user/group to systemd-userwork
    # (same pattern as weston-init for the weston user)
    install -d ${D}${nonarch_libdir}/userdb
    install -m 0644 ${S}/kiosk.user ${D}${nonarch_libdir}/userdb/
    install -m 0644 ${S}/kiosk.group ${D}${nonarch_libdir}/userdb/

    # tmpfiles.d: create /home/kiosk and /run/user/810 at boot
    install -d ${D}${nonarch_libdir}/tmpfiles.d
    install -m 0644 ${S}/kiosk-runtime.conf ${D}${nonarch_libdir}/tmpfiles.d/
}

FILES:${PN} = " \
    ${nonarch_libdir}/userdb/kiosk.user \
    ${nonarch_libdir}/userdb/kiosk.group \
    ${nonarch_libdir}/tmpfiles.d/kiosk-runtime.conf \
"
