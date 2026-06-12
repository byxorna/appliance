# Post-Install Configuration

## WiFi

WiFi is supported but not configured by default. There are two options:

### Option 1: Pre-configure at build time

Place a config file at `local/wpa_supplicant.conf` in the repo root before building. The `local/` directory is gitignored, so your secrets stay out of version control.

```bash
mkdir -p local
cat > local/wpa_supplicant.conf <<'EOF'
ctrl_interface=/var/run/wpa_supplicant
ctrl_interface_group=0
update_config=1
country=US

network={
    ssid="MyNetwork"
    psk="MyPassword"
    key_mgmt=WPA-PSK
}
EOF
make build
```

If no `local/wpa_supplicant.conf` exists, the image ships with an unconfigured stub.

### Option 2: Configure at runtime on the device

```bash
wpa_passphrase "MyNetwork" "MyPassword" >> /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
systemctl restart wpa_supplicant@wlan0
```

## Bluetooth

The image includes BlueZ 5, the BCM4345C0 HCD firmware, and the `pi-bluetooth` helper services. Bluetooth should be functional on first boot.

### Verify

```bash
# Check the firmware loaded successfully (look for "BCM4345C0" with no errors)
dmesg | grep -i bluetooth

# Check the bthelper and bluetooth services are running
systemctl status hciuart
systemctl status bluetooth

# Verify the adapter is up
hciconfig hci0

# Scan for nearby devices
bluetoothctl power on
bluetoothctl scan on
```

### Troubleshooting

If `hciconfig` shows no device or `dmesg` reports firmware load failures:

```bash
# Confirm the firmware file is present
ls -l /lib/firmware/brcm/BCM4345C0.hcd

# Check if hciuart failed to attach the UART transport
journalctl -u hciuart -b

# Restart the BT stack
systemctl restart hciuart
systemctl restart bluetooth
```

## App Containers

Each application runs as a podman container managed by a systemd service (`appliance-app-<name>.service`). The container's environment, mounts, and devices are configured at build time through the app's `app.json` manifest. Operators can customize container behavior at runtime without rebuilding.

### Environment variables

Each app reads `/data/apps/<name>/env` at container start. This is a plain-text file with one `KEY=VALUE` per line. Comments (`#`) and blank lines are allowed. Values set here override any defaults baked into the image.

```bash
# Example: point Feishin at a specific Navidrome server
cat >> /data/apps/feishin/env <<'EOF'
NAVIDROME_URL=http://music.local:4533
EOF

systemctl restart appliance-app-feishin
```

The file lives on the persistent `/data` partition and survives rootfs updates. It's created empty on first boot if missing.

### Viewing container state

```bash
# Service status and recent logs
systemctl status appliance-app-feishin
journalctl -u appliance-app-feishin -f

# Inspect the running container
podman inspect appliance-app-feishin

# Shell into a running container
podman exec -it appliance-app-feishin /bin/sh

# List all app containers
podman ps --filter 'name=appliance-app-'
```

### Restarting an app

```bash
systemctl restart appliance-app-feishin
```

The container is replaced on each start (`--replace --rm`), so restarts are clean.
