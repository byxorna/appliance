# meta-appliance-apps

Application recipes for the appliance OS. Each app lives under `recipes-apps/<name>/` and inherits `appliance-app.bbclass` from `meta-appliance-os`.

## Apps

- **[Feishin](https://github.com/jeffvli/feishin)** — Music player frontend for Navidrome/Jellyfin. Repackaged upstream arm64 AppImage running as a native Wayland Electron app on VT 2.
