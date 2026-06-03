# reTerminal display rotation: the 720x1280 portrait DSI panel needs
# rotate-270 to present landscape.  This weston.ini overrides the
# rotation-free base config from meta-appliance-os.
FILESEXTRAPATHS:prepend := "${THISDIR}/weston-init:"
