# Ship a wpa_supplicant.conf so WiFi can work out of the box (or be
# pre-configured at build time without committing secrets to git).
#
# Priority order:
#   1. local/wpa_supplicant.conf  (user-supplied, gitignored)
#   2. files/wpa_supplicant.conf-default  (unconfigured stub with examples)

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://wpa_supplicant.conf-default"

WPA_CONF_FILE = "wpa_supplicant.conf-default"
python () {
    import os
    repo_root = d.getVar('REPO_ROOT')
    local_dir = os.path.join(repo_root, 'local')
    user_conf = os.path.join(local_dir, 'wpa_supplicant.conf')
    if os.path.isfile(user_conf):
        d.prependVar('FILESEXTRAPATHS', local_dir + ':')
        d.appendVar('SRC_URI', ' file://wpa_supplicant.conf')
        d.setVar('WPA_CONF_FILE', 'wpa_supplicant.conf')
        bb.note("wpa-supplicant: using user-supplied config from %s" % user_conf)
    else:
        bb.note("wpa-supplicant: no local/wpa_supplicant.conf found, using default stub")
}

inherit systemd

SYSTEMD_SERVICE:${PN}:append = " wpa_supplicant@wlan0.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# The systemd template unit wpa_supplicant@wlan0.service looks for
# /etc/wpa_supplicant/wpa_supplicant-wlan0.conf.  Install our config there
# so it works out of the box on first boot.
do_install:append () {
    install -d -m 0700 ${D}${sysconfdir}/wpa_supplicant
    install -m 0600 ${WORKDIR}/${WPA_CONF_FILE} ${D}${sysconfdir}/wpa_supplicant/wpa_supplicant-wlan0.conf
}

FILES:${PN} += "${sysconfdir}/wpa_supplicant/wpa_supplicant-wlan0.conf"
