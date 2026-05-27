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
