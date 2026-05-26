# Backlog

Items to address in future phases. Not yet planned or scoped.

## Hardware button UX

- **Function key overlays (green button hold):** While holding the green button, show a visual overlay labeling the F1-F3 keys with context-sensitive actions (e.g. play/pause, next track, toggle shuffle when Feishin is focused). Overlay disappears on release.
- **App switcher (green button double-tap):** Double-tap green button to cycle between running applications. Future apps: Home Assistant dashboard alongside Feishin.
- **Power button blanks/wakes screen:** Short press blanks display (DPMS off or backlight off). Press again to wake. Not a shutdown — the appliance stays running.

## USB storage

- **Auto-mount USB sticks:** Plug in a USB drive and its media library appears in Feishin immediately — no user interaction required. Goal is walk-up "DJ" use: plug stick, browse, play. Needs udev rules, automount (udisks2 or a lightweight systemd automount), and Feishin/Navidrome configured to scan the mount point.

## Audio output

- **USB DAC support (USB Type-C):** Primary DAC is a USB Type-C device. Must be detected and selected as default ALSA/PipeWire output without manual configuration.
- **Class-compliant USB audio:** Any USB Audio Class 1/2 compliant device should work as an output — not just the specific DAC. Kernel `CONFIG_SND_USB_AUDIO`, proper udev/PipeWire routing, and a sensible default-device policy (prefer USB over HDMI/headphone jack).

## Future applications

- **Home Assistant:** Second appliance app alongside Feishin. Needs app switcher UX above.
