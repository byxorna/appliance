# Pin SRCREV to avoid AUTOREV in the upstream recipe.
# master HEAD 2026-05-26. Includes scarthgap build fix, panel crash fix,
# and 6.12/6.18 compat patches (version-guarded, confirmed building
# cleanly against the 6.1 kernel).
SRCREV = "c336085a3a60a39afcc64fd784ec27dca71dbed2"

# ---------------------------------------------------------------------------
# Appliance button fixups  (applied before compile)
# ---------------------------------------------------------------------------
# pwr_btn  (top-edge power button, GPIO 13):
#   KEY_SLEEP (142) -> KEY_POWER (116) so logind handles
#   tap-to-blank + long-press-to-shutdown.  Drop autorepeat.
# MCP23008 buttons (F1/F2/F3/O):
#   Remove gpio-key,wakeup — the I2C expander IRQ cannot be a wakeup
#   source (returns -EINVAL, causing a suspend-fail loop).
# ---------------------------------------------------------------------------

do_compile:prepend() {
    DTS="${S}/overlays/rpi/reTerminal-overlay.dts"

    # F1-O (usr_btn0-3): drop gpio-key,wakeup (MCP23008 IRQ can't do it)
    for btn in usr_btn0 usr_btn1 usr_btn2 usr_btn3; do
        sed -i "/${btn}:\s*${btn}/,/};/ {
            /gpio-key,wakeup;/d
        }" "$DTS"
    done

    # pwr_btn: KEY_SLEEP (142) -> KEY_POWER (116), drop autorepeat
    sed -i '/pwr_btn:\s*pwr_btn/,/};/ {
        s|linux,code = <142>;.*|linux,code = <116>; /* KEY_POWER */|
        /autorepeat;/d
    }' "$DTS"
}
