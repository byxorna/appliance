# meta-appliance-os

Platform layer for the reTerminal HiFi Appliance. Provides the appliance-os distro configuration, BSP tuning, platform services, and the appliance-os-image recipe.

This layer contains all platform concerns. Application layers (meta-appliance-app-*) depend on this layer and inherit `appliance-app.bbclass` for the app manifest contract.
