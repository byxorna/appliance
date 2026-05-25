# meta-kiosk-os

Platform layer for the reTerminal HiFi Appliance. Provides the kiosk-os distro configuration, BSP tuning, platform daemons (kiosk-init, kiosk-shell, kiosk-buttond, kiosk-playd, kiosk-httpd, kiosk-updater), and the kiosk-os-image recipe.

This layer contains all platform concerns. Application layers (meta-kiosk-app-*) depend on this layer and inherit `kiosk-app.bbclass` for the app manifest contract.
