# meta-kiosk-app-feishin

Application layer for [Feishin](https://github.com/jeffvli/feishin), a music player frontend for Navidrome and Jellyfin servers.

Builds Feishin's web mode (`pnpm run build:web`) and packages it as a kiosk app with `app.json` manifest. Served on port 9180. Integrates with the platform's playback coordinator via the `kiosk-playback-shim.js` MediaSession hook.
