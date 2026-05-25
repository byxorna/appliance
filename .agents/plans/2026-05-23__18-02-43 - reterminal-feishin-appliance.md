# Kiosk OS Platform for reTerminal - Plan

## Requirements

A generic kiosk/appliance OS platform for the Seeed reTerminal (CM4, 4GB RAM, 32GB eMMC, 5" 720x1280 DSI touchscreen) that:

1. Boots into a fullscreen kiosk shell that hosts one or more web applications.
2. Hardware buttons drive an in-shell control surface: transport controls (F1-F3) routed through a central playback coordinator, plus a dedicated app-switcher / settings button (F4). The coordinator decouples buttons from whichever app currently owns playback.
3. Immutable root filesystem with A/B partition scheme.
4. Atomic updates: download bundle, stage to inactive slot, reboot, auto-rollback on failure.
5. Persistent user/app config survives updates.
6. No manual maintenance. No apt, no DKMS, no patching.
7. Pluggable application architecture: the OS platform is generic, applications are swappable modules.
8. First application: Feishin (music player frontend for Navidrome/Jellyfin).
9. Future: multi-room playback coordination, companion webapp, iOS app. Not in MVP scope.

## Detailed Implementation Plan + Reasoning

### Architecture: platform, shell, and applications

The system splits into three concerns:

**Platform layer** (the OS): handles hardware, display, compositor, browser runtime, networking, updates, persistent storage, audio stack. Knows nothing about what apps run on it.

**Shell layer** (kiosk-shell): a lightweight web app shipped by the platform. Chromium always points at the shell. The shell provides:
- An app switcher overlay, triggered by hardware button or touch gesture.
- An iframe/navigation host that loads the active app's URL.
- A status bar or indicator showing which app is active (minimal, can be hidden).
- A WebSocket connection to `kiosk-buttond` for receiving hardware button events.
- A settings panel (system info, WiFi, update trigger, audio output selection).

**Application layer**: web apps served locally, each in its own HTTP server instance on its own port. Delivered as self-contained directories of static files (HTML/JS/CSS) plus an `app.json` manifest describing config schema, required capabilities (audio, network, bluetooth, etc.), and startup parameters.

This separation means:
- Adding/removing apps = adding/removing a directory + manifest. No shell or platform changes.
- App updates can be independent of OS updates (app bundle vs. OS bundle).
- The same OS image works for a music player, a home dashboard, a digital signage display, or any combination.
- Multiple apps can be installed and switched between at runtime.

### Hardware button mapping

The reTerminal has 4 user buttons (GPIO via MCP23008 I/O expander at I2C 0x38) and 1 power button (GPIO 13). Linux exposes these as `/dev/input/eventX` key events via the gpio-keys driver in the reTerminal DT overlay.

A small daemon (`kiosk-buttond`) reads these input events and routes them. The shell maps non-power buttons to actions:

| Button | Short press | Long press | Routed to |
|--------|------------|------------|-----------|
| F1 (user btn 1) | Play / pause | - | `kiosk-playd` (coordinator) |
| F2 (user btn 2) | Previous track | Volume down (repeat) | `kiosk-playd` |
| F3 (user btn 3) | Next track | Volume up (repeat) | `kiosk-playd` |
| F4 (user btn 4) | Toggle app switcher | Open settings overlay | `kiosk-shell` |
| Power (short) | Screen on/off (DPMS) | - | `systemd-logind` (HandlePowerKey=ignore + daemon-handled) |
| Power (long, >2s) | Shutdown | - | `systemd-logind` (HandlePowerKeyLongPress=poweroff) |

**Button routing config.** `kiosk-buttond` ships a routing table at `/etc/kiosk-buttond/routes.toml` (overridable from `/data/platform/kiosk-buttond/routes.toml`). Each evdev key code is mapped to a destination: `coordinator` (forward to `kiosk-playd` as a playback command), `shell` (forward to `kiosk-shell` over its WebSocket), `power` (handle locally: short = DPMS toggle via DRM ioctl on `/dev/dri/card0`; long = `systemctl poweroff`), or `drop`. The default routing matches the table above. Apps and the shell never see playback button events directly; the coordinator never sees app-switcher events. This avoids ambiguity about who consumes which press.

**Power button handling.** systemd-logind is configured with `HandlePowerKey=ignore` and `HandlePowerKeyLongPress=ignore` so the kernel power-button keypress falls through to `kiosk-buttond`. The daemon implements: short press toggles display power via `drmModeSetCrtc` blanking on `/dev/dri/card0` (no compositor restart, instant on/off, app state preserved); long press (>2s held) calls `systemctl poweroff`. Rationale for handling DPMS in the daemon instead of letting logind do it: logind's idle/lid handling assumes a desktop, not a kiosk; the daemon already owns input and has a tight feedback loop with the compositor.

Playback commands (F1-F3) go through the playback coordinator. They always control whichever app currently holds the playback provider role, regardless of which app is in the foreground. This means the user can browse a different app while transport controls keep working for the music player.

Button-to-action mappings (which key triggers play vs. next, long-press thresholds, etc.) are stored in `/data/platform/kiosk.json` and can be remapped. The defaults above optimize for the primary use case (HiFi appliance with dedicated transport controls + one button for system UI).

Why a dedicated daemon instead of injecting synthetic keypresses into Chromium: the shell needs structured events (button ID, press/release/long-press), not raw keycodes. A WebSocket carrying JSON messages (`{"button": "f1", "action": "press"}`) is cleaner than trying to intercept keyboard events in a sandboxed browser context. The daemon is ~100 lines of C or Python using libinput/evdev.

### IR remote support

An IR receiver (e.g., TSOP38238) connected to a GPIO pin provides a standard media remote control. The kernel's RC (Remote Controller) subsystem decodes IR protocols (NEC, RC5, RC6, Sony, etc.) and emits input events at `/dev/input/eventX`, just like the GPIO buttons.

Hardware setup:
- IR receiver data pin wired to **GPIO 24** on the reTerminal 40-pin header. (GPIO 18 is *not* available: it carries I2S BCLK to the WM8960 audio codec on the reTerminal expansion board. GPIOs 18-21 are reserved for I2S audio. GPIO 24 is free on the standard reTerminal pinout.)
- Enabled via the `gpio-ir-recv` DT overlay, already available in meta-raspberrypi: `dtoverlay=gpio-ir,gpio_pin=24`.
- The overlay creates an RC input device. No out-of-tree modules needed.
- Pin choice must be re-verified against the reTerminal expansion-board schematic before the first hardware bring-up. Track as a Phase 2 task.

Integration with `kiosk-buttond`:
- `kiosk-buttond` already reads evdev devices. The IR receiver is just another `/dev/input/eventX` source. On startup, the daemon scans for all input devices matching either the MCP23008 gpio-keys node or an RC device (by capabilities or name), and polls them all.
- IR events carry standard `KEY_*` codes (KEY_PLAYPAUSE, KEY_NEXTSONG, KEY_PREVIOUSSONG, KEY_VOLUMEUP, KEY_VOLUMEDOWN, KEY_MUTE, etc.). The daemon's routing table treats these as additional sources for the same logical commands as F1-F3 (and so they go to `kiosk-playd`); arrow keys / OK / back / menu go to `kiosk-shell` for switcher navigation.
- IR remote gets priority 100 (same as hardware buttons). It's a dedicated physical control, same as the GPIO buttons. The 2-second preemption window applies identically.

Default keymap: a standard NEC remote (the most common protocol for cheap IR remotes). The kernel ships NEC keymaps, and `ir-keytable` (v1.16+) loads custom keymaps in the **TOML format documented by `ir-keytable(1)`** (sections `[[protocols]]` with `name`, `protocol`, and `[protocols.scancodes]` tables mapping hex scancode -> `KEY_*` symbol). The platform stores the active keymap at `/data/platform/ir-keymap.toml`. If no custom keymap exists, the default ships in `/etc/rc_keymaps/default-kiosk.toml`. A systemd unit `kiosk-ir-keytable.service` loads it on boot via `ir-keytable -c -w /etc/rc_keymaps/default-kiosk.toml -s <rc-device>` (with the data-partition path preferred if present).

Relevant `config.txt` addition:
```
dtoverlay=gpio-ir,gpio_pin=24
```

The GPIO pin is configurable at build time via a variable in `reterminal.conf` and at runtime by editing `/boot/config.txt` from the data partition (or via a future settings UI).

Why this approach: the kernel RC subsystem already handles protocol decoding, repeat filtering, and keymap management. `kiosk-buttond` doesn't need to know anything about IR protocols. It just reads evdev events. This keeps the daemon simple and lets users swap remotes or remap keys without touching the daemon.

### App switching model

The shell always runs. It hosts the active app via an iframe pointing at `http://localhost:<app-port>/<entry>`. Switching apps is initiated only two ways:

1. User presses **F4** (short press: open switcher overlay; tap an app tile to activate; long press: settings).
2. User taps an app in the switcher overlay (touchscreen, or via IR remote arrow keys when present).

On activation:

1. Shell transitions the iframe src to the new app's URL.
2. Previous app's HTTP server keeps running (see iframe lifecycle policy below for which iframes stay warm).
3. Shell updates the active-app indicator.

F1/F2/F3 never switch apps. They always go to the playback coordinator, which routes them to whichever app currently owns the playback-provider role, regardless of which app is in the foreground. Browsing one app while music keeps playing in another is a first-class case.

The iframe model means apps are sandboxed. They can't interfere with each other or the shell. The shell can overlay UI on top of any app (notifications, volume control, now-playing indicator, button hints).

**Iframe lifecycle policy.** The shell keeps the foreground iframe and the active playback-provider iframe warm; other apps have their HTTP server running but no iframe, and are created on demand. Per-origin storage (`localStorage` / `IndexedDB`) survives teardown because the origin is unchanged.

### Playback coordinator (`kiosk-playd`)

Central problem: multiple input sources (hardware buttons, shell touch UI) need to send playback commands and receive playback state. Without coordination, each source needs app-specific wiring, and preemption semantics are ad-hoc.

`kiosk-playd` is a platform daemon that mediates between command sources and playback providers. It owns the canonical playback state and arbitrates who controls what. All communication is WebSocket on `ws://localhost:8082`. Command sources and providers both connect to it.

#### Protocol

JSON over `ws://localhost:8082`. Roles: `source` (sends commands), `provider` (executes + reports state), `observer` (receives state). Verbs: play, pause, next, prev, seek, volume, shuffle, repeat. Exact message schema lives in `kiosk-playd` source.

#### Priority and preemption

Each command source has a priority level:

| Source | Priority | Behavior |
|--------|----------|----------|
| Hardware buttons | 100 | Always wins. Immediate execution. |
| IR remote | 100 | Same as hardware buttons. Dedicated physical control. |
| Shell touch UI | 80 | Normal interactive use. |

Preemption semantics:
- Commands are always executed (no queueing). Priority determines tie-breaking when two sources send conflicting commands within the same 100ms window.
- After a hardware button or IR remote press, the coordinator sets a brief "hardware active" flag suppressing lower-priority sources, so soft sources can't immediately undo a hardware action.
- State updates always flow to all observers regardless of priority.

The preemption window is configurable in `kiosk.json`. For most use cases, the default 2s is sufficient. If a user is actively using hardware buttons, rapid presses naturally extend the window.

#### Active provider selection

Only one provider is "active" at a time (receives commands). Rules:

1. The most recently registered provider that reported a non-idle state is active.
2. If multiple providers are registered, the one in the foreground app gets priority.
3. If the foreground app has no provider (e.g., a non-media app is in front), the last active provider keeps receiving commands. This lets transport buttons work while browsing a different app.
4. Explicit handoff: an app can send `{"type": "provider.yield"}` to release active status.

**Provider liveness and disconnects.** Provider sockets use a heartbeat + grace window so an iframe reload (common on app switch + return) reconnects without UI flap. A genuine crash exceeds the window; the provider is dropped, the now-playing bar clears, and active-provider selection re-runs. Timeouts and queue depth are tunable in `kiosk-playd` config.

#### App-side integration: the playback shim

Apps that support playback include a small JS library (`kiosk-playback-shim.js`, shipped by the platform in a well-known URL) that:

1. Connects to `ws://localhost:8082` and registers as a provider.
2. Receives commands (`play`, `pause`, `next`, etc.) and translates them to app-specific actions.
3. Reports state changes back to the coordinator.

The shim is app-specific in its command translation. For Feishin, it hooks into Feishin's internal player API (or intercepts the MediaSession API that Feishin already uses). The platform ships a generic shim base class; each app provides a thin adapter.

The shim file is served by the shell's HTTP server at `http://localhost:8080/sdk/playback-shim.js`. Apps load it via a script tag or dynamic import. The app manifest declares `"capabilities": ["playback"]` to signal that the shim should be available.

For the Feishin integration specifically: Feishin's web build uses HTML5 `<audio>` (via `react-player` / `wavesurfer.js`) and the standard `navigator.mediaSession` API for metadata + transport controls. The shim hooks `mediaSession.setActionHandler` to receive play/pause/next/prev/seek from the coordinator, and reads `mediaSession.metadata` plus the audio element's state for now-playing reporting. No Feishin-internal patching is required for transport; if seek-position reporting via `mediaSession.positionState` proves unreliable, fallback is a tiny content script that reads `currentTime` from the audio element directly.

#### Feishin web-mode capability summary

Validated against upstream Feishin v1.11 (de-risked 2026-05-23). The renderer is environment-aware via `is-electron` -- Electron-only code paths short-circuit cleanly in a plain browser, and Electron-only UI controls hide themselves. **No fork or patch is required.**

| Capability                          | Electron build | Web build (kiosk)         |
|-------------------------------------|----------------|---------------------------|
| HTML5 audio playback                | yes            | **yes** (only backend)    |
| MPV backend                         | yes            | no                        |
| MediaSession API (transport)        | yes            | **yes** (our shim hook)   |
| Server-embedded `.lrc` lyrics       | yes            | **yes**                   |
| MPRIS / OS media keys               | yes (Linux)    | no (replaced by buttond)  |
| Native auto-update                  | yes            | no (RAUC supersedes)      |
| Encrypted password store            | yes            | no (UI hides setting)     |
| Visualizer (butterchurn)            | yes            | **yes**                   |
| Scrobbling                          | yes            | **yes**                   |
| Runtime config via env vars         | no             | **yes** (`settings.js`)   |

None of the "no" rows is a blocker for this appliance.

#### Shell now-playing overlay

The shell subscribes to the coordinator as an observer. When any provider reports playback state, the shell can show a persistent now-playing indicator: track title, artist, album art. This works regardless of which app is in the foreground.

The now-playing bar is a thin strip at the bottom of the screen (above the iframe). Tapping it switches to the provider's app. It auto-hides when playback is idle.

### App manifest contract

Each application provides an `app.json` manifest:

```json
{
  "name": "feishin",
  "version": "1.11.0",
  "display_name": "Feishin",
  "icon": "icon.svg",
  "entry": "index.html",
  "port": 9180,
  "capabilities": ["audio", "network", "playback"],
  "config_dir": "feishin",
  "color": "#1a1a2e",
  "env": {
    "SERVER_LOCK": "false"
  }
}
```

`icon` and `color` are used by the shell's app switcher overlay. `port` must be unique across installed apps (enforced at build time by `kiosk-app.bbclass`). `capabilities` includes `playback` for apps that integrate with the playback coordinator via the shim.

The platform reads all installed manifests at boot to start HTTP servers, wire up config directories, and populate the shell's app registry.

### App delivery model

For MVP, apps ship baked into the rootfs. One OS bundle = one OS + its bundled apps. Updates are whole-image (rootfs A/B); there is no separate app-update path yet.

On-rootfs app location: `/usr/share/kiosk-apps/<name>/` for each installed app. No single "active" symlink; all installed apps are available, the shell manages which is in the foreground.

The manifest contract and directory structure (see below) are designed so a future `appfs` RAUC slot class can be added without breaking existing apps. That work is explicitly out of MVP scope -- see Out of Scope -- and is not referenced elsewhere in the MVP body of this plan.

### Build system: Yocto + meta-raspberrypi + meta-seeed-cm4

Why not Buildroot: Chromium cross-compilation is better supported in Yocto via meta-browser/meta-chromium. Buildroot's Chromium support is less mature for ARM64.

Why not Debian + mender-convert: Tempting for speed, but breaks the "no apt, no DKMS, no patching" requirement. Debian rootfs is mutable by nature. mender-convert bolts A/B onto it, but the image isn't reproducible and every build is a snowflake.

Why not NixOS: ARM64 support improving but still rough. Closure sizes are large. Boot generation model is similar to A/B but more complex for embedded.

Yocto gives: reproducible bit-for-bit images, proper cross-compilation, mature CM4 BSP, and clean integration paths for RAUC and Chromium. The build is slow (hours), but you do it in CI, not on-device.

### Update mechanism: RAUC

Why not Mender: Open-source Mender has no delta updates. RAUC with casync gives reasonable deltas. RAUC is also lighter, no mandatory server component, and the D-Bus API is clean for triggering updates from whatever app is running.

Why not SWUpdate: Also viable. RAUC wins on simplicity for a pure A/B rootfs swap. SWUpdate's power (asymmetric updates, FPGA handlers, Lua scripting) is overkill here.

Why not OSTree: Better delta efficiency, but significantly more complex integration. RAUC A/B is conceptually simpler, easier to debug, and well-documented for Yocto + RPi.

### Display: shell + apps in Chromium kiosk

The platform runs `chromium-ozone-wayland` in kiosk mode under Cage. Chromium loads the shell at `http://localhost:8080` (fixed port, platform-owned). The shell hosts individual apps via iframes to their respective ports.

Why Chromium and not a lighter browser (like Cog/WPE): Chromium's Web Audio API, media codec support, and DevTools are significantly more complete. For a HiFi music player (and future apps), full Chromium is worth the image size.

### Compositor: Cage (single-app Wayland kiosk)

Cage is a single-application Wayland compositor using wlroots. Runs one app fullscreen with no window chrome. Perfect for kiosk. Available in meta-oe or easily added.

### reTerminal hardware support

The reTerminal needs 4 out-of-tree kernel modules (`mipi_dsi` for the 5" 720x1280 DSI panel, `ltr30x` ambient light, `lis3lv02d` accelerometer, `bq24179_charger`) plus device tree overlays (`reTerminal.dtbo`, `reTerminal-bridge.dtbo`). Seeed maintains all of these in one repo, `Seeed-Studio/seeed-linux-dtoverlays`, and already packages them for Yocto in `Seeed-Studio/meta-seeed-cm4` with `MACHINE = "seeed-reterminal"`.

We consume `meta-seeed-cm4` as an upstream BSP layer rather than writing our own module/overlay recipes. This is a deliberate change from earlier plans of porting the modules in-tree to our `meta-kiosk-os` layer: Seeed's recipes are MIT-licensed, actively maintained (latest release `2025-04-03-reTerminal-V2.0` supports kernel 6.12, last commit Jul 2025), and the layer is used by their commercial products, so kernel-bump churn is largely absorbed upstream.

Display rotation (panel is 720x1280 portrait, target is 1280x720 landscape) is handled by Cage's output transform (`transform 270`) combined with the DT overlay's `tp_rotate=1`. Both are required; see the rotation alignment test in Phase 2.

**BSP layer lifecycle.** `meta-seeed-cm4` is upstream code, treated like any other vendor BSP:

- **Versioning.** `meta-seeed-cm4` is pinned by `SRCREV` in our kas file. Bumping it is an intentional PR with a hardware smoke test, never `${AUTOREV}`. Same rule for `seeed-linux-dtoverlays` if we ever need to override its SRCREV in a bbappend.
- **Kernel-bump churn.** When meta-raspberrypi advances the kernel, Seeed usually catches up within weeks (their commit history shows kernel 6.6 support added Mar 2024, 6.12 support added Apr 2025). If meta-raspberrypi moves faster than Seeed, we defer the kernel bump — same release discipline as before, but the work is largely "wait for the upstream commit" rather than "patch four modules ourselves."
- **Worst case (Seeed abandons the repo).** Fork `meta-seeed-cm4` and `seeed-linux-dtoverlays` into our own infra and assume direct maintenance. Mirror both to our `downloads/` CI store so we are not exposed to GitHub takedowns. Documented as a risk in `docs/risks.md` but no longer the expected case.
- **Upstreaming watch.** `ltr30x` and `lis3lv02d` have plausible mainline equivalents that just need DT bindings. If a mainline driver appears, drop the out-of-tree binding in `seeed-linux-dtoverlays` and bind the in-tree driver via DT overlay override. Low priority while Seeed is maintaining their version.
- **Module load order.** Same as before: `mipi_dsi` loaded early via `/etc/modules-load.d/`, sensors come up via udev when their I2C devices appear. Sensor module failure is logged and non-fatal (e.g., ambient-light auto-brightness silently disabled).

**What we override from meta-seeed-cm4.** The layer's default reTerminal image autostarts qtdemo and pulls `meta-qt5`. We don't want Qt. We strip it via:

- `IMAGE_INSTALL:remove = "qtdemo packagegroup-seeed-qt"` (or equivalent) in our image recipe
- Avoid adding `meta-qt5` to our kas layer list at all if possible; if `meta-seeed-cm4` has a hard `LAYERDEPENDS` on it, satisfy the parse-time dep but never install any Qt packages into the image
- Use `MACHINE = "seeed-reterminal"` from `meta-seeed-cm4` but our own `DISTRO = "kiosk-os"` (no Qt features, Wayland-only, no X11)

**What we don't take from meta-seeed-cm4.** They ship Mender-enabled variants of their image recipes. We use RAUC instead (see Phase 7), so we ignore the `*-mender.yml` kas files and write our own image recipe that consumes the BSP without the update mechanism.

### Partition layout

```
/dev/mmcblk0p1  boot     (FAT32, ~128MB) - shared, RPi firmware + U-Boot + config.txt + cmdline.txt + boot.scr
/dev/mmcblk0p2  rootfs-a (ext4, ~8GB)    - immutable, read-only mount; carries its own /boot/Image + /boot/dtbs/
/dev/mmcblk0p3  rootfs-b (ext4, ~8GB)    - immutable, read-only mount; carries its own /boot/Image + /boot/dtbs/
/dev/mmcblk0p4  data     (ext4, ~14GB)   - persistent, survives updates
```

**Kernel placement: per-slot, inside the rootfs.** The shared FAT holds only firmware blobs and U-Boot. Each rootfs slot carries its own kernel image and DTB at `/boot/Image` and `/boot/dtbs/bcm2711-rpi-cm4.dtb`. U-Boot reads the active slot's partition (via `raucslot`/`BOOT_DEV` env vars), then `load mmc 0:${slotpart} ${kernel_addr_r} boot/Image` directly from the rootfs ext4. This is the pattern used by `meta-rauc-community/meta-rauc-raspberrypi` (changed deliberately in commit `ce49d53` on 2024-06-25) and by `cdsteinkuehler/br2rauc`. RAUC writes only the inactive rootfs partition during update; the active slot's kernel is never touched because it lives inside the active rootfs, not in a shared location.

Shared FAT contents:
- RPi GPU firmware: `start4.elf`, `start4cd.elf`, `fixup4.dat`, `fixup4cd.dat`
- `config.txt` (sets `kernel=u-boot.bin`, enables 64-bit, configures the DPI display via the overlays-need-flag path -- see Phase 2)
- `cmdline.txt` (slot-agnostic kernel command line; U-Boot overrides `root=` per slot at boot time)
- `u-boot.bin` (single U-Boot binary, loaded by the RPi firmware)
- `boot.scr` (compiled U-Boot script handling slot selection, attempt-counter decrement, kernel/DTB load from the chosen rootfs)

The boot partition can stay at the typical ~128MB; with kernel + DTB out of the FAT, there's plenty of room for two copies of `u-boot.bin` and a future `boot-mbr-switch` setup (see below).

The data partition holds:

- `/data/apps/<app-name>/` - per-app config and state
- `/data/platform/rauc/` - RAUC keyring and state
- `/data/platform/network/` - NetworkManager connections (WiFi creds)
- `/data/platform/machine-id` - stable machine identity
- `/data/platform/timezone` - timezone config
- `/data/platform/kiosk.json` - platform-level config (installed apps order, default app, button mappings, display settings, update server URL)
- `/data/platform/ir-keymap.toml` - custom IR remote keymap (loaded by ir-keytable on boot, optional)

rootfs mounts read-only. Writable paths are bind-mounted from /data by a platform init service that reads the app manifest and wires up the right directories.

### Persistent data: platform vs. app config

The platform owns `/data/platform/`. Apps own `/data/apps/<name>/`. Neither can write to the other. The platform init service is responsible for:

1. Reading `/data/platform/kiosk.json` for platform config (button mappings, default app, update server).
2. Scanning `/usr/share/kiosk-apps/*/app.json` to discover all installed apps.
3. For each app: creating `/data/apps/<config_dir>/` if missing, bind-mounting it, and starting its HTTP server.

The full boot sequence (including coordinator, button daemon, shell HTTP server, and Cage startup ordering) is specified in detail in the "kiosk-init boot sequence" section below.

Adding a new app requires: static files + manifest in a `meta-kiosk-app-*` layer. No platform or shell changes.

### Bootloader: U-Boot

meta-raspberrypi supports U-Boot (`RPI_USE_U_BOOT = "1"`). Required for RAUC integration because the stock RPi firmware bootloader has no concept of boot attempt counters or slot switching. U-Boot provides the redundant env area (`CONFIG_ENV_IS_IN_MMC=y`, `CONFIG_SYS_REDUNDAND_ENVIRONMENT=y`, two copies at MMC offsets 0x100000 and 0x200000, 32K each) that RAUC reads/writes via `fw_setenv`/`fw_printenv`, and the boot script that implements slot selection.

**Concrete env variables (set in `boot.scr`):**

- `BOOT_ORDER="A B"` -- priority order
- `BOOT_A_LEFT=3`, `BOOT_B_LEFT=3` -- per-slot attempt counters
- `BOOT_DEV` -- derived per slot: `mmc 0:2` for A, `mmc 0:3` for B
- `raucslot` -- derived per slot: `A` or `B`, passed to userspace via `rauc.slot=` kernel arg
- `bootargs` -- derived per slot: `root=/dev/mmcblk0p2 rauc.slot=A rootwait ro` (or `p3`/`B` for slot B); `rootwait` is mandatory on eMMC because the controller enumerates asynchronously

Boot script flow: iterate `BOOT_ORDER`, pick first slot whose `BOOT_<X>_LEFT > 0`, decrement via `setexpr`, save env, set `BOOT_DEV` + `bootargs`, then `load ${BOOT_DEV} ${kernel_addr_r} boot/Image && load ${BOOT_DEV} ${fdt_addr_r} boot/dtbs/bcm2711-rpi-cm4.dtb && booti ${kernel_addr_r} - ${fdt_addr_r}`.

RAUC ties slots to env via `bootname=A` in `[slot.rootfs.0]` and `bootname=B` in `[slot.rootfs.1]` in `system.conf`. `/etc/fw_env.config` matches the U-Boot offsets so userspace `fw_setenv` writes to the same area U-Boot reads. RAUC's `mark-good` systemd service confirms successful boot after critical services are up by resetting the counter. Hardware watchdog (BCM2835 WDT) catches hangs.

### CM4 boot quirks (out of RAUC's scope)

The BCM2711 SPI-EEPROM bootloader and the GPU firmware blobs (`start*.elf`, `fixup*.dat`) are not managed by RAUC. They live in the SPI EEPROM and on the FAT respectively.

- **EEPROM updates** require either `rpi-eeprom-update` running on the device, or USB-rpiboot via the J2 jumper (pin 93 `nRPIBOOT`) on the reTerminal. We ship `rpi-eeprom` but don't auto-update; field EEPROM updates are a manual support procedure for MVP.
- **No hardware boot partitions.** Do not use eMMC `boot0`/`boot1`. The BCM2711 EEPROM cannot read them; everything boots from the user partition (`mmcblk0`).
- **`rootwait` is mandatory** in the kernel cmdline for eMMC boot -- the eMMC controller enumerates asynchronously after kernel start.
- **RPi firmware watchdog window: 16s.** From cold start, U-Boot must reach a stage that either disables or pets the firmware watchdog within 16 seconds, otherwise the firmware resets. U-Boot's RPi support handles this when configured correctly; verify on first-boot test.

### Bootloader/firmware update strategy (FAT atomicity)

For MVP: accept the meta-rauc-community approach of writing `u-boot.bin`, `config.txt`, `boot.scr`, and GPU firmware to the shared FAT non-atomically. Rationale: bootloader/firmware updates will be rare (likely never within MVP), can require AC power, and the cost of a mid-update power loss here is "user re-flashes via USB rpiboot" -- the same recovery path we already document for bricked-beyond-recovery. With per-slot kernels living inside the rootfs, kernel updates -- the actually frequent kind of update -- are already atomic through the RAUC rootfs swap.

**Post-MVP follow-up:** Adopt `boot-mbr-switch` (br2rauc's pattern using RAUC's native MBR partition-table swap between two FAT copies at offsets 4M and 260M) when we need atomic bootloader updates. Not in the MVP critical path.

### Update flow

1. Device checks update server (simple HTTPS endpoint, or manual trigger).
2. Downloads RAUC bundle (.raucb), signed SquashFS containing the new rootfs image (which already includes `/boot/Image` and `/boot/dtbs/bcm2711-rpi-cm4.dtb`) and a manifest.
3. RAUC installs to the inactive slot: writes the rootfs ext4 image to the inactive rootfs partition, verifies checksums. The shared FAT is **not touched** for kernel updates -- the new kernel comes along inside the new rootfs.
4. RAUC updates the U-Boot env via `fw_setenv`: bumps `BOOT_ORDER` to put the inactive slot first, resets `BOOT_<inactive>_LEFT=3`.
5. User (or auto) triggers reboot.
6. U-Boot reads env, boots the new slot: loads `boot/Image` and `boot/dtbs/bcm2711-rpi-cm4.dtb` from the new rootfs partition, decrements `BOOT_<new>_LEFT`.
7. If boot succeeds and `rauc-mark-good` runs, the counter resets and the new slot is permanent.
8. If boot fails (kernel panic, hang, services don't start), watchdog or manual reboot. Counter decrements. After `BOOT_<new>_LEFT` reaches 0, U-Boot falls back to the old slot (whose rootfs -- and therefore kernel -- was never touched).

Update server for MVP: static file hosting (S3 bucket, nginx dir listing). RAUC bundle + a version manifest JSON. The on-device updater checks manifest, compares version, downloads if newer.

### Recovery scenarios

What the device does when the update path fails in various ways, in increasing order of severity:

- **Network drops mid-download.** kiosk-updater resumes via HTTP `Range:` requests if the server supports it; otherwise it restarts the download on next attempt. Partial bundles in `/var/cache/rauc/` are checksum-verified before install — a corrupt bundle is discarded, not installed.
- **Signature verification fails.** RAUC refuses to install. Bundle deleted, error logged to journald and to `/data/platform/logs/upgrade-<timestamp>.log`. Active slot remains active and bootable. User-visible: "Update failed: signature invalid" in settings.
- **Install succeeds but new slot fails to boot (kernel panic, hang, services don't start).** This is the watchdog/attempt-counter path covered in the Update flow section. After N=3 boot attempts, U-Boot falls back to the old slot. RAUC marks the failed slot as bad on first boot after fallback. User-visible: "Last update reverted" notification in settings on the recovered slot, with the failure logs from the failed slot's `/data/platform/logs/` (which survives because `/data` is shared across slots).
- **Both slots are broken.** Should not happen in practice (the active slot is only marked good after services are up), but if `/data/` is corrupt or some platform-wide config kills both slots: the device boots to a degraded shell that shows only the diagnostics page and the factory-reset option. Implementation: kiosk-init catches a startup failure of `kiosk-shell.service` after 3 attempts, falls back to launching a minimal "recovery shell" (a small static HTML page baked into the rootfs at `/usr/share/kiosk-recovery/`) that exposes log download and the factory-reset trigger over the touchscreen.
- **eMMC write failure / data partition unmountable.** kiosk-init detects mount failure of `/data`, attempts `fsck -y`, and on persistent failure boots to the recovery shell (same as above) which offers "reformat data partition" — same code path as factory reset, but skipping the wipe-then-reformat dance since the partition is already inaccessible.
- **Bricked beyond recovery.** Last resort: user re-flashes the full `.wic` image via USB. The reTerminal has a USB-C port that supports `rpiboot` (CM4's BootROM USB boot mode). Documented in the support docs. Requires opening no enclosure — the USB-C port is exposed. The user's `/data/` is preserved across a re-flash only if they explicitly choose a "preserve data" option in the flashing tool; the standard re-flash wipes everything.

### Audio output

Platform-level concern, not app-specific. The platform ships PipeWire + ALSA. Apps that declare the `audio` capability get audio routed through the browser's Web Audio API, which hits PipeWire/ALSA.

Supported outputs for MVP:
- USB DAC (USB audio class, no special driver needed, primary HiFi path)
- HDMI audio
- Built-in WM8960 codec (via reTerminal-bridge overlay, adequate for monitoring)

**HiFi / bit-perfect path (USB DAC).** Routing audio from Chromium's Web Audio through PipeWire to a USB DAC has two quality risks: Chromium's internal mixer often resamples to a fixed rate (commonly 48kHz), and PipeWire's default graph adds another resampling stage. To maximize fidelity:

- PipeWire is configured with `default.clock.allowed-rates = [ 44100 48000 88200 96000 176400 192000 ]` and `default.clock.rate = 48000` so the graph can lock to the source-track sample rate when a single client streams. The relevant config drops into `/etc/pipewire/pipewire.conf.d/10-kiosk-hifi.conf`.
- USB DAC sink node is created with `node.latency = 1024/48000`, `audio.format = S24_3LE` (or `S32_LE` depending on the DAC's reported best format from `pw-dump`), and `session.suspend-timeout-seconds = 0` so the DAC isn't power-cycled between tracks.
- The Chromium recipe is built with the audio-resampler tuned (no built-in resample where avoidable); but Chromium *will* still go through Web Audio. The honest expectation is "near-bit-perfect for 44.1k and 48k content when the graph locks; resampled with a high-quality resampler otherwise." True bit-perfect playback of 24/96 or 24/192 source material from a web frontend cannot be guaranteed; if that becomes a hard requirement, the fallback is to bypass the browser by exposing a small native MPD/MPV-based player that the Feishin web UI controls over its API, scheduled for post-MVP under "native playback path".
- The settings UI exposes the active sample rate / format so the user can verify what the DAC is actually receiving.

Track as a Phase 6 task: validate the realized path with `pw-top`, `pw-dump`, and the DAC's own indicator LEDs / display showing native-rate lock.

### Logging and diagnostics

The eMMC has a finite write-endurance budget, so the default systemd-journald target is volatile RAM. A small persistent ring is kept for the specific events whose value comes from surviving a crash or rollback.

- **journald (volatile, primary).** `Storage=volatile`, journal directory tmpfs-backed at `/run/log/journal`. `SystemMaxUse=64M`, `RuntimeMaxUse=64M`. All app servers, kiosk-playd, kiosk-buttond, Cage, Chromium logs land here. Lost on reboot.
- **journald (persistent ring, secondary).** A small per-boot snapshot at `/data/platform/logs/journal/` capped at 32MB total (`SystemMaxUse=32M`, `SystemMaxFiles=4`). `Storage=auto` for this directory only via a drop-in. This survives reboots and is what gets pulled for post-mortem after a failed update or unexpected reboot.
- **RAUC pre/post hooks.** `pre-install` and `post-install` hooks (and `marked-good` / `marked-bad`) copy a slice of journald (`journalctl -b -0 --since "10 minutes ago"`) into `/data/platform/logs/upgrade-<timestamp>.log`. Last 5 upgrade logs retained. This is the audit trail when an update bricked the device and U-Boot rolled back; the recovered slot still has these files.
- **Boot/early-init.** kiosk-init writes a short structured boot record (`/data/platform/logs/boot-<timestamp>.json`: timestamp, kernel cmdline, active slot, mark-good status, app discovery summary). Last 20 boots retained. Useful for spotting "device rebooted at 3am every night" type symptoms without trawling the full journal.
- **Log access.** The shell exposes a "Diagnostics" page in settings: pulls journald via `journalctl -e -n 500 --no-pager` and renders it. A "Download diagnostic bundle" button tarballs `/data/platform/logs/` + recent journald + `rauc status` output + `pw-dump` output for support purposes. No automatic upload.
- **Application logs.** Each app's HTTP server logs to journald via systemd, tagged with `_SYSTEMD_UNIT=kiosk-app-<name>.service`, filterable in the diagnostics view.
- **Chromium logs.** Chromium is launched with `--enable-logging=stderr --log-level=1` so its output is captured by journald; the verbose log file (`chrome_debug.log`) is disabled to avoid eMMC writes.

### Time synchronization

The CM4 has no battery-backed RTC. At boot the kernel clock starts at the build-stamped epoch (`systemd-timesyncd` reads `/usr/lib/clock-epoch` if shipped, otherwise the filesystem mtime). This creates an ordering problem: HTTPS to the update server requires a sane clock (TLS cert validation) but NTP requires network, which on first boot also requires WiFi provisioning to have completed.

- **Daemon.** `systemd-timesyncd` is used (already part of systemd, no extra recipe). Configured via `/etc/systemd/timesyncd.conf` with `NTP=pool.ntp.org` and `FallbackNTP=time.cloudflare.com time.google.com`. User can override the server list via `/data/platform/kiosk.json` -> `time.ntp_servers`; kiosk-init renders a drop-in at `/run/systemd/timesyncd.conf.d/10-kiosk.conf` from that config.
- **Boot ordering.** `systemd-time-wait-sync.service` is enabled and required by `kiosk-updater.service` so the updater cannot run with an unsynced clock. App services do not depend on time-sync (apps can start with a wrong clock; only the updater cares).
- **No-network case.** If NTP cannot reach a server within 60s, `systemd-time-wait-sync` times out and the updater stays blocked until next network event. The shell's settings page shows "Clock not synchronized" with last-sync timestamp. Apps run normally with whatever clock the kernel has.
- **TLS chicken-and-egg.** `systemd-timesyncd` uses unauthenticated NTP (port 123, UDP); no TLS dependency. Once synced, RAUC's HTTPS bundle download has a valid wall clock for cert validation. This is the standard order: NTP first, TLS second.
- **Persistence.** `systemd-timesyncd` writes the last-known time to `/data/platform/time/clock` on graceful shutdown; on next boot the kernel clock is bumped forward to at least that value (`ConditionFileNotEmpty=` drop-in invokes `date -s` via a small oneshot before timesyncd starts). This keeps the post-reboot clock monotonic-ish even without network.
- **Drift expectation.** Without RTC and with periodic NTP sync (default daily), expect clock accuracy within seconds when online, and "frozen at last-sync time + uptime" when offline.

### Factory reset

The device must be recoverable to a known clean state without disassembly. Two entry points:

- **Hardware trigger (no UI required).** Hold F4 + power button together for >5 seconds during the early-boot window. kiosk-init reads evdev state from `/dev/input/event*` (buttons enumerate before kiosk-shell is up) immediately after udev settle; if both keys are held continuously for 5s while the boot splash is showing, the daemon wipes `/data/` (rm -rf with the partition's mountpoint preserved), writes a "factory_reset_pending" marker to `/data/platform/state/`, and reboots. The mount is then re-formatted on next boot if the marker is present (`mkfs.ext4 -F /dev/disk/by-partlabel/data`). The wipe + reformat are intentionally two reboots to recover from a corrupted data partition (where rm-rf would itself fail).
- **Software trigger.** Settings -> "Factory reset" in the shell. Shows a confirmation dialog, then writes the same `factory_reset_pending` marker and reboots. Same code path as the hardware trigger from that point.
- **What is wiped.** Everything under `/data/` (platform config, app config, persistent logs, time/clock cache, WiFi profiles, RAUC's per-slot status files that live under `/data`). The rootfs slots are untouched; whichever slot was active before remains active after reset.
- **What survives.** Active RAUC slot, both rootfs slots' code, U-Boot env (which contains slot-selection state — intentional, so a half-broken slot doesn't trap the user post-reset).
- **First-boot detection after reset.** The standard first-boot path runs (no `/data/platform/kiosk.json`), forcing WiFi provisioning, default app selection, etc.
- **Documentation.** Boot splash text or a small printed sticker references the F4+power gesture so a user who has forgotten their WiFi config or app credentials can recover.

### First-time WiFi provisioning

The CM4 on the reTerminal has Broadcom WiFi (brcmfmac). The device ships with no network credentials and no keyboard; provisioning has to work from the touchscreen alone, with an out-of-band escape hatch for the headless / broken-touch case.

- **Network manager.** `NetworkManager` is the platform's network daemon (chosen over systemd-networkd because the shell needs runtime APIs for scan/connect, and NetworkManager exposes them via D-Bus). Connection profiles persist to `/data/platform/network/system-connections/` via a bind mount over `/etc/NetworkManager/system-connections/`.
- **MVP path: on-device touch flow.** On first boot, if NetworkManager reports no saved connections and no carrier, kiosk-init flips the shell into a "first-time setup" mode (a query param on the shell URL). The shell shows a WiFi setup screen: list of visible SSIDs (`nmcli -t -f SSID,SIGNAL device wifi list`), tap to select, on-screen keyboard for passphrase (using the standard browser virtual keyboard, triggered by `inputmode="text"` on a `<input>`), connect via NetworkManager D-Bus. Connection success unlocks the rest of the shell.
- **Fallback path: file drop on boot partition.** The boot partition is FAT32 and is readable/writable from any host OS. If a file `wifi.conf` exists at the root of the boot partition on boot, kiosk-init imports it: parses `ssid=`, `psk=` (and optional `hidden=true`, `priority=N`), writes a NetworkManager keyfile to `/data/platform/network/system-connections/`, then deletes `wifi.conf` from the boot partition (so credentials don't sit in plaintext on a removable filesystem). This is the recovery path when the touch UI is unreachable.
- **WPS / push-button.** Not in MVP. Out of scope.
- **Enterprise / 802.1X.** Not in MVP; user must use the file-drop method to deploy an EAP keyfile.
- **Captive portal.** Not detected or handled in MVP; the device assumes home/private networks.
- **Change WiFi later.** Settings -> "Network" page in the shell lists saved connections, allows forget/edit/add. Same NetworkManager D-Bus interface.
- **Ethernet.** USB-Ethernet adapters and the optional reTerminal Ethernet expansion work out of the box via NetworkManager's default DHCP profile, no provisioning needed; if ethernet is up at first boot, the WiFi setup screen is skipped (but still reachable from settings).

### Security model

The device is a home appliance assumed to live on a trusted LAN behind NAT. The threat model is "casual misuse and supply-chain hygiene", not "nation-state on the local network". Concrete posture:

- **Image signing.** RAUC bundles signed with an x.509 cert; the device's rootfs contains only the public cert in `/etc/rauc/keyring.pem`. Private key lives in the CI secret store, accessible only to release-tag jobs. Unsigned or mis-signed bundles are refused, no override.
- **TLS for updates.** The update server is HTTPS-only. Standard system CA bundle is shipped (from `ca-certificates` recipe). Update URL is configurable but defaults to a vendor-controlled HTTPS endpoint. No certificate pinning in MVP (relies on system CA chain).
- **SSH access.** Disabled by default in release images. Dev images include `dropbear` with key-only auth (no passwords); authorized_keys deployed at image build via the developer's pubkey. Toggling SSH on a release image requires a factory-reset-style hold-button sequence at boot, or a developer USB stick with a recognized recovery script — explicit future work, not in MVP.
- **Local services binding.** `kiosk-playd`, `kiosk-buttond`, `kiosk-httpd`, and per-app HTTP servers all bind to `127.0.0.1` only. Nothing is exposed on the LAN.
- **Browser sandboxing.** Chromium runs with its standard renderer sandbox (`--enable-features=` defaults, no `--no-sandbox`). Apps live in separate iframes from separate origins. Mechanism: kiosk-init writes one `/etc/hosts` entry per installed app (`127.0.0.1  app-<name>.kiosk.local`) and configures each app's nginx server block to respond on that hostname. The shell loads the iframe with `src="http://app-<name>.kiosk.local:<port>/"`, so each app gets a distinct origin tuple `(scheme, host, port)` and cross-app DOM/cookie/storage isolation is enforced by the browser's Same-Origin Policy. The shell itself stays on `http://localhost:8080/` (privileged origin). Earlier sections of this plan use `http://localhost:<port>/` as shorthand when port-uniqueness alone matters; the canonical per-app URL form is the `app-<name>.kiosk.local` one defined here.
- **Same-origin shim API.** The shell-to-app `postMessage` shim validates the `origin` field on every message and rejects messages whose origin doesn't match a known app's `app-<name>.kiosk.local:<port>` tuple. Apps cannot impersonate other apps.
- **Filesystem isolation.** Apps cannot write outside `/data/apps/<name>/`. Enforced via app systemd unit's `ReadWritePaths=` / `ProtectSystem=strict` settings and the bind-mount layout from kiosk-init.
- **User account.** All platform daemons run as a dedicated unprivileged `kiosk` user (uid in the 900s, system range). The `root` account is locked (`!` in `/etc/shadow`); no password login possible anywhere. systemd manages all services.
- **Secrets at rest.** WiFi PSKs, Feishin/Navidrome/Jellyfin credentials, scrobble tokens — all live in `/data/` unencrypted. Full-disk encryption is not in MVP (it would require a TPM or user-typed unlock, and a kiosk has no keyboard at boot). The threat model treats physical-possession-of-device as "game over" already.
- **Dependency provenance.** Yocto recipes pin upstream sources by SHA256 (`SRC_URI[sha256sum]`). License audit runs in CI (`do_populate_lic` reports). No automatic-version recipes (`AUTOREV`) in production images.
- **CVE tracking.** `meta-security`'s `cve-check` class runs in CI nightly, flags recipes with open CVEs. Triage is manual; criticals block a release.

### Crash handling and watchdogs

The device is unattended; everything has to either self-recover or fail loudly enough to surface in diagnostics. Per-component policy:

- **Hardware watchdog.** BCM2835 WDT enabled via `dtparam=watchdog=on`. `systemd` is configured with `RuntimeWatchdogSec=30s` and `RebootWatchdogSec=2min`. If userspace (PID 1) stops feeding the watchdog, the hardware resets the device. Catches full-system hangs.
- **App HTTP server crashes.** Each app runs under a systemd unit (`kiosk-app-<name>.service`) with `Restart=on-failure` and `RestartSec=2s`. `StartLimitBurst=5`, `StartLimitIntervalSec=60s`: 5 crashes in 60s puts the unit into `failed` state and stops auto-restart. The shell notices the unit is failed (polls `systemctl is-active` or watches the D-Bus signal) and shows the app's tile with an "App stopped" badge; tapping it re-enables and restarts the unit.
- **Coordinator (kiosk-playd) crashes.** `Restart=always`, `RestartSec=1s`. App provider iframes are designed to reconnect transparently (see "Provider liveness and disconnects" subsection). A coordinator crash in steady state means a 1-2s gap in transport-button responsiveness, no visible app impact.
- **Button daemon (kiosk-buttond) crashes.** Same `Restart=always` policy. While down, hardware buttons do nothing; touch UI is unaffected. Audible warning is not in MVP.
- **Cage (compositor) crashes.** `Restart=always`. A Cage crash takes Chromium with it (Wayland session gone). Chromium is launched as a child of Cage so they restart together. User-visible: screen blanks for 2-5s then the shell reloads. Apps lose in-memory state (per the iframe lifecycle policy, persistent state is in localStorage/IndexedDB on the data partition; the next foreground iframe re-mounts and re-hydrates).
- **Chromium crashes (within a running Cage).** Chromium has its own multi-process model; a renderer crash shows the standard "Aw, snap" page in the affected iframe. The shell detects this via `<iframe>` `load`-event timing and `error` events; it offers a "Reload app" button. A browser-process crash brings down the whole UI; Cage's `Restart=always` brings Chromium back.
- **kiosk-init crashes.** `Restart=on-failure`, `StartLimitBurst=3`. Three failures in a row trips the "boot the recovery shell" path described in Recovery scenarios.
- **Out-of-memory.** systemd-oomd enabled with default thresholds. Chromium's per-tab memory limits are tuned via flags (`--js-flags="--max-old-space-size=512"` per iframe). The iframe LRU eviction policy (max 2 live iframes) is the primary OOM-prevention mechanism. If systemd-oomd kills a process, the relevant `Restart=` policy picks it up.
- **Crash dumps.** Core dumps are disabled by default in release images (`LimitCORE=0` in systemd) to avoid eMMC writes. In dev images, core dumps are written to `/var/lib/systemd/coredump/` (tmpfs) and viewable via `coredumpctl`; not persistent.
- **Failure surfaces.** All of the above land in journald, which is included in the diagnostic bundle. The settings "Diagnostics" page shows the count of recent service restarts and the last restart timestamp per unit, so a user can spot "Feishin restarted 47 times last hour" without leaving the touchscreen.

### Layer stack

Upstream Yocto + BSP layers used as-is, plus two custom layers we own:

```
poky (scarthgap 5.0 LTS)
  meta-openembedded (meta-oe, meta-python, meta-networking, meta-multimedia)
  meta-raspberrypi (scarthgap branch)
  meta-seeed-cm4 (main branch, tracks scarthgap; provides MACHINE=seeed-reterminal, kernel modules, DT overlays)
  meta-clang (scarthgap branch, required by meta-chromium)
  meta-browser/meta-chromium (scarthgap branch)
  meta-rauc (scarthgap branch)
  meta-kiosk-os (custom layer - platform)
  meta-kiosk-app-feishin (custom layer - feishin app recipe)
```

Yocto scarthgap (5.0, the current LTS) was chosen over wrynose (6.0, current stable but not LTS) because `meta-seeed-cm4`'s `main` branch tracks scarthgap and they ship `v1.0.0` tagged against it. Tracking the BSP layer's preferred release avoids carrying a backport branch. Revisit when Seeed publishes a wrynose-tracking branch.

The two custom layers enforce the platform/app boundary at build time (see Architecture section for why). The next section details what lives inside each. A different app (e.g., Home Assistant dashboard, digital signage) is a separate `meta-kiosk-app-*` layer; the image recipe picks which app layers to include.

### Custom layer structure

```
meta-kiosk-os/
  conf/
    layer.conf
    distro/
      kiosk-os.conf                     # distro config (systemd, wayland, pipewire, etc.)
  classes/
    kiosk-app.bbclass                   # base class for app recipes (installs to /usr/share/kiosk-apps/, validates manifest)
  recipes-bsp/
    reterminal-config/
      reterminal-config.bb              # config.txt fragments, modules-load.d ordering, gpio-ir overlay enablement (consumes meta-seeed-cm4 for the actual modules/DT overlays)
  recipes-core/
    images/
      kiosk-os-image.bb                 # base image recipe, pulls in platform + installed apps
    rauc/
      rauc-conf.bbappend                # RAUC system.conf + keyring
    kiosk-init/
      kiosk-init.bb                     # systemd service: discovers apps, wires bind-mounts, starts servers
  recipes-platform/
    cage/
      cage_%.bbappend                   # output transform for reTerminal rotation
    chromium/
      chromium-ozone-wayland_%.bbappend # kiosk flags, disable URL bar, touch tuning
    kiosk-shell/
      kiosk-shell.bb                    # the shell web app (app switcher, settings, iframe host)
      files/
        shell/                          # shell static files (HTML/JS/CSS)
    kiosk-buttond/
      kiosk-buttond.bb                  # hardware button + IR remote -> WebSocket bridge daemon, routes playback commands via kiosk-playd
    kiosk-playd/
      kiosk-playd.bb                    # playback coordinator daemon (WebSocket :8082, state + command routing)
      files/
        playback-shim.js                # base JS shim for apps to integrate with coordinator
    kiosk-httpd/
      kiosk-httpd.bb                    # lightweight HTTP server (nginx), templated per-app from manifests
    kiosk-updater/
      kiosk-updater.bb                  # update check + download service, app-agnostic
  conf/machine/
    reterminal.conf                     # machine config (extends raspberrypi4-64)
  wic/
    kiosk-os.wks.in                     # partition layout

meta-kiosk-app-feishin/
  conf/
    layer.conf
  recipes-app/
    feishin/
      feishin-web_git.bb                # builds Feishin web app from source (node/pnpm)
      files/
        app.json                        # Feishin app manifest
```

### kiosk-app.bbclass contract

Any app recipe inherits `kiosk-app` and must:

1. Install static web files to `${D}/usr/share/kiosk-apps/${KIOSK_APP_NAME}/www/`.
2. Install `app.json` to `${D}/usr/share/kiosk-apps/${KIOSK_APP_NAME}/app.json`.
3. Optionally install `icon.svg` to `${D}/usr/share/kiosk-apps/${KIOSK_APP_NAME}/icon.svg`.
4. Set `KIOSK_APP_NAME` in the recipe.

The class validates the manifest schema at build time, checks port uniqueness across all apps in the image, and registers the app.

The image recipe sets `KIOSK_DEFAULT_APP = "feishin"` (which app the shell shows on first boot). All apps included in the image are available for switching. The default can be changed at runtime via `/data/platform/kiosk.json`.

### kiosk-init boot sequence

systemd service (Type=oneshot, Before=cage.service):

1. Mount /data if not mounted.
2. Read `/data/platform/kiosk.json`. If missing, create defaults (default_app from KIOSK_DEFAULT_APP baked into rootfs, default button mappings).
3. Scan `/usr/share/kiosk-apps/*/app.json` to discover installed apps.
4. For each installed app:
   a. Create `/data/apps/<config_dir>/` if missing.
   b. Bind-mount app config directory.
   c. Generate nginx server block (port, document root, `server_name app-<name>.kiosk.local`, env vars from manifest).
   d. Start the app via `systemctl start kiosk-app@<name>.service` (a systemd template unit shipped by kiosk-httpd that runs nginx with the per-app server block and applies the sandbox flags from the Security model section: ReadWritePaths, ProtectSystem=strict, PrivateTmp, etc.).
   e. Append `127.0.0.1 app-<name>.kiosk.local` to `/etc/hosts` (kiosk-init owns this file; rewritten on every boot from the discovered app set).
5. Generate shell config: write `/run/kiosk/shell.json` with app registry (names, ports, icons, colors, default app) and button mappings.
6. Start shell HTTP server (port 8080, serves shell static files + `/api/apps` endpoint backed by shell.json).
7. Start `kiosk-playd` daemon (playback coordinator, port 8082). Must start before kiosk-buttond, which connects to playd for F1-F3 routing.
8. Start `kiosk-buttond` daemon (port 8081).
9. Generate Cage launch config (URL = `http://localhost:8080`).

Then Cage starts Chromium pointed at the shell. Shell reads its config, renders the default app in its iframe, and begins listening for button events.

### kiosk-shell architecture

The shell is a small, self-contained web app (vanilla JS or Preact, no heavy framework). Ships as static files in the platform layer, not as a kiosk-app (it's privileged, not user-swappable).

Components:
- **App host**: a full-viewport iframe. `src` set to the active app's URL.
- **App switcher overlay**: grid of installed app icons/names. Triggered by F4 button or swipe-from-edge gesture. Tapping an app sets the iframe src. Animated transition.
- **Status bar** (optional, hideable): shows active app name, clock, WiFi indicator. Thin strip at top edge, auto-hides after 3s.
- **Settings panel**: accessible from app switcher. Shows: system info (version, IP, slot), WiFi config, audio output, button remapping, update check/install trigger.
- **Now-playing bar**: thin strip at bottom edge, shows track/artist/art from the active playback provider. Tapping it switches to the provider's app. Auto-hides when idle.
- **WebSocket clients**: connects to `ws://localhost:8081` (kiosk-buttond) for button/IR events and `ws://localhost:8082` (kiosk-playd) for playback state. Dispatches button events to handler based on mapping; playback commands (F1-F3 or IR media keys) are forwarded to kiosk-playd, app switching (F4) handled directly.

The shell serves a REST-ish API at `http://localhost:8080/api/`:
- `GET /api/apps` - list installed apps (from shell.json)
- `GET /api/platform` - system info, update status
- `GET /api/playback` - current playback state (snapshot from coordinator)
- `POST /api/platform/update/check` - trigger update check
- `POST /api/platform/update/install` - trigger RAUC install (calls kiosk-updater via D-Bus or unix socket)
- `WS /api/playback/ws` - proxy to kiosk-playd for real-time playback control

### First-boot experience

1. Device powers on, U-Boot loads kernel, boots into rootfs-a.
2. kiosk-init runs, finds no `/data/platform/kiosk.json`, creates defaults; detects no NetworkManager profiles and no ethernet carrier, so it sets the `first_run=1` flag passed to the shell.
3. kiosk-init checks for `wifi.conf` at the root of the boot partition; if present, imports it into `/data/platform/network/system-connections/` and deletes it from the boot partition (see "First-time WiFi provisioning").
4. kiosk-init discovers installed apps (e.g., Feishin) and starts their HTTP servers, plus `kiosk-playd`, `kiosk-buttond`, and the shell's HTTP server.
5. Cage starts, Chromium loads the shell.
6. Because `first_run=1`, the shell opens the first-time setup flow: WiFi setup screen (scanned SSIDs, on-screen keyboard via `inputmode="text"`). Ethernet skips this. The `wifi.conf` import path also skips this on subsequent boots.
7. Once connected (or skipped via ethernet), shell clears `first_run` in `/data/platform/kiosk.json` and loads the default app (Feishin) in the iframe.
8. Feishin shows its server configuration screen (no Navidrome/Jellyfin server configured yet).
9. User enters Navidrome/Jellyfin server URL + credentials in Feishin UI.
10. Music plays. Feishin's playback shim connects to kiosk-playd, registers as provider.
11. Config saved to `/data/apps/feishin/`.
12. User can press F1 to pause/resume, F2/F3 for prev/next track (routed through coordinator).
13. User can press F4 to open app switcher (only Feishin installed, but settings panel and now-playing bar are functional).

### Build and CI

- GitHub Actions or similar CI builds the Yocto image.
- Produces: full .wic image (for initial flash) + RAUC .raucb bundle (for updates).
- Uploads bundle to update server.
- Devices pull updates from there.

**CI infrastructure requirements.** Yocto + Chromium is the long pole. A from-scratch image build with Chromium is 4-8 hours on a 16-core x86_64 host with 32GB RAM; with a warm `sstate-cache` and `downloads/` mirror, incremental builds (only the layers you changed) typically take 15-45 minutes. Plan accordingly:

- **Runner specs.** 16+ vCPU, 32+GB RAM, 150GB+ disk. GitHub Actions "large" runners (`ubuntu-latest-16-core` or self-hosted) meet this; the default 4-core/16GB runner does not (Chromium link step alone needs ~16GB RAM and will OOM).
- **`sstate-cache` persistence.** sstate is what makes incremental builds tractable. Persisted to an external store (S3 bucket, Cachix-style server, or a self-hosted directory exposed via HTTPS) and pulled at job start. The cache key is hashed on `(MACHINE, DISTRO, layer revisions, recipe checksums)` — Yocto already produces these hashes. Stale cache is harmless (it gets rebuilt); missing cache just means a long build.
- **`downloads/` (DL_DIR) mirror.** All upstream tarballs/git checkouts mirrored to the same store. Avoids the build breaking when an upstream forge is down and reduces upstream load. `BB_GENERATE_MIRROR_TARBALLS = "1"` to produce snapshots of git fetches.
- **Build matrix.** Single MACHINE (`raspberrypi4-64`) for MVP, single DISTRO. Add release vs. dev image variants later if needed.
- **Cold-cache budget.** First build of a new Chromium major version (or a clean cache) is the 4-8h case. Plan for this once per Chromium upgrade. Scheduled nightly "warm cache" build keeps sstate fresh against drift; on-PR builds use that warm cache.
- **Artifact retention.** `.wic` images are large (~2GB), `.raucb` bundles smaller (~400MB compressed). Retain the last 30 days of bundles on the update server; CI keeps the last N builds as job artifacts for triage.
- **Branch policy.** `main` produces dev-channel bundles. Release tags (`v*`) produce stable-channel bundles, signed with the production RAUC signing key (stored as a CI secret, only released-channel jobs have access).
- **Test stages.** PR builds: layer parsing (`bitbake-layers show-recipes`), recipe checksums, license audit, do a do_fetch dry run, build only the platform image (skip Chromium-heavy app images). Main/tag builds: full image build + RAUC bundle. Hardware-in-the-loop tests are a stretch goal (a CI-owned reTerminal that auto-flashes and runs a smoke suite).

### What's explicitly out of scope for MVP

- Multi-room / multi-zone playback (coordinator protocol supports zones, but implementation deferred)
- Companion webapp / iOS app for remote playback control (the shell + coordinator APIs are designed for it; auth, pairing, and network exposure deferred)
- Delta/incremental updates (full rootfs swap is fine for 8GB images over WiFi)
- Captive portal WiFi provisioning (see WiFi first-config section for what *is* in MVP)
- Automatic update polling (manual trigger via SSH or future UI button)
- Separate `appfs` RAUC slot and per-app OTA updates independent of OS (apps ship in rootfs for now)

## Task List

### Phase 0: Project scaffolding
- [ ] Create project repo with meta-kiosk-os and meta-kiosk-app-feishin layers
- [ ] Set up kas configuration for reproducible Yocto builds (scarthgap LTS, pinned SRCREV for every layer including meta-seeed-cm4)
- [ ] Write layer.conf for both layers
- [ ] Document build prerequisites (host packages, disk space, RAM)
- [ ] Mirror upstream sources to our own infra: poky, meta-openembedded, meta-raspberrypi, meta-seeed-cm4, seeed-linux-dtoverlays, meta-clang, meta-browser, meta-rauc (so a vendor takedown doesn't brick CI)

### Phase 1: Minimal bootable image
- [ ] Set up Yocto scarthgap with meta-raspberrypi, MACHINE=raspberrypi4-64
- [ ] Add U-Boot configuration
- [ ] Build and test core-image-minimal on CM4 (boots, serial console works)

### Phase 2: reTerminal hardware support
- [ ] Add meta-seeed-cm4 to kas layer list (pinned SRCREV, scarthgap-tracking main branch)
- [ ] Switch image to MACHINE=seeed-reterminal (inherits raspberrypi4-64, adds overlays + modules)
- [ ] Write reterminal-config.bb (config.txt fragments for our use case, /etc/modules-load.d ordering, gpio-ir overlay for IR receiver on GPIO 24)
- [ ] Define DISTRO=kiosk-os to exclude Qt features pulled by meta-seeed-cm4 defaults; IMAGE_INSTALL:remove qtdemo and any Qt session packages
- [ ] Verify IR receiver pin choice against the reTerminal expansion-board schematic (default GPIO 24; confirm no I2S / SPI / UART overlap)
- [ ] Build and test: display works, touchscreen works, all 4 buttons + power button emit evdev events, modules load in the expected order (`lsmod | grep -E 'mipi_dsi|ltr30x|lis3lv02d|bq24179'`)
- [ ] Verify front-bezel LEDs enumerate as `/sys/class/leds/usr_led{0,1,2}` (USR green, STA red, STA green) via the reTerminal overlay's MCP23008. Consumed by `kiosk-vumeter` in Phase 6.
- [ ] **Rotation alignment test**: with Cage configured for `transform 270` *and* the touch DT overlay `tp_rotate=1`, run a small test page that prints `(touch.clientX, touch.clientY)` at the contact point. Tap each of the 4 screen corners and the center; verify the reported coordinates match expected pixel positions for a 1280x720 landscape buffer (within ~10px). If misaligned, iterate on the combination of compositor transform and DT `tp_rotate` until corners and center line up. Capture the final combination as the canonical setting in `reterminal-config.bb` and the Cage bbappend.

### Phase 3: Platform kiosk infrastructure
- [ ] Add meta-clang, meta-chromium to layer stack
- [ ] Add Cage compositor
- [ ] Write kiosk-app.bbclass (app manifest contract, install paths, port uniqueness validation)
- [ ] Write kiosk-init service (app discovery, per-app bind-mount wiring, per-app server config generation)
- [ ] Write kiosk-httpd recipe (nginx, generates a server block per installed app from manifests)
- [ ] Configure Chromium kiosk mode (fullscreen, no UI chrome, touch-friendly)
- [ ] Configure display rotation in Cage (DSI-1, transform 270)
- [ ] Build and test with a trivial "hello world" test app: server starts, correct port, files served

### Phase 4: Shell + button daemon

Note on phase ordering: Phase 4 and Phase 4b can be developed in parallel, but the F1-F3 acceptance test below requires kiosk-playd to be present. Either complete Phase 4b first, or stub kiosk-playd with a minimal WebSocket server on :8082 that accepts connections and logs commands, and revisit the acceptance test after Phase 4b lands.

- [ ] Write kiosk-shell web app (iframe host, app switcher overlay, settings panel, now-playing bar, dual WebSocket client)
- [ ] Write kiosk-buttond daemon (evdev reader for reTerminal buttons + IR receiver, WebSocket server on :8081, connects to kiosk-playd for playback commands)
- [ ] Wire shell to kiosk-init (shell.json generation from discovered apps + button mappings)
- [ ] Build and test with 2 trivial test apps: shell loads, F4 switches app switcher, settings panel opens
- [ ] Test button event flow: press F1-F3, verify events reach shell (requires Phase 4b or kiosk-playd stub)
- [ ] Test IR input: send NEC commands from IR LED or `ir-ctl`, verify events reach shell with same behavior as hardware buttons

### Phase 4b: Playback coordinator
- [ ] Write kiosk-playd daemon (WebSocket server on :8082, command routing, state broadcasting, priority/preemption logic)
- [ ] Write playback-shim.js base library (provider registration, command handler interface, state reporting)
- [ ] Wire kiosk-buttond F1-F3 to send playback commands through coordinator
- [ ] Wire shell to subscribe to coordinator as observer (now-playing bar)
- [ ] Build and test with a mock playback provider: send play/pause/next via buttons, verify state broadcast to shell

### Phase 5: Feishin app

**De-risked (2026-05-23):** Feishin's web build is a first-class, upstream-supported deployment mode, not a fork-required hack. Evidence:

- Dedicated build script: `pnpm run build:web` → `vite build --config web.vite.config.ts` → static bundle at `out/web/`.
- PWA-configured (vite-plugin-pwa: manifest, service worker, icons).
- Officially shipped as `ghcr.io/jeffvli/feishin` Docker image (nginx-unprivileged serving the static bundle on port 9180 — exactly the port we already reserved).
- Renderer never imports `electron` directly. All Electron access routes through `window.api` (preload contextBridge). Renderer uses the `is-electron` package to gate Electron-only code paths and hide Electron-only UI controls.
- Runtime configuration via env-injected `settings.js.template`: `SERVER_LOCK`, `SERVER_NAME`, `SERVER_TYPE`, `SERVER_URL`, `REMOTE_URL`, `LEGACY_AUTHENTICATION`, `ANALYTICS_DISABLED`, `PUBLIC_PATH`, plus `FS_*` first-run defaults. A single static build is configured at deploy time, no rebuild needed.

**Web-build feature gaps (versus Electron build):** MPV backend (web uses HTML5 `<audio>` via `react-player` / `wavesurfer.js`), MPRIS / OS media keys (irrelevant on this kiosk — `kiosk-buttond` → `kiosk-playd` replaces it), Discord RPC, native auto-update (we use RAUC instead — strictly better), `electron-store` + `safeStorage` encrypted password store (the UI hides the password-store settings via `isHidden: !isElectron()`), external lyric scraping via NetEase/lrclib (server-embedded lyrics still work — Navidrome and Jellyfin can both serve `.lrc` files), mDNS server autodiscover, native download shell-handler, power-save blocker. None of these is a blocker for our use case.

**Audio implication:** Web-mode Feishin plays via the browser's HTML5 audio element. Audio leaves Chromium through Web Audio → PipeWire → ALSA → USB DAC / HDMI. There is no MPV in the audio path. The bit-perfect-path discussion in the Audio output section continues to apply (Chromium's resampler is the bottleneck, not MPV).

**Build strategy for the recipe:** `feishin-web_git.bb` clones upstream at a pinned tag, runs `pnpm install --frozen-lockfile` then `pnpm run build:web`, and ships `out/web/` plus `ng.conf.template` + `settings.js.template`. The app's HTTP server is a tiny nginx (or we reuse `kiosk-shell`'s server with appropriate static-file routes; decided in the recipe). The app.json declares `port: 9180` and `capabilities: ["playback"]`. The runtime `settings.js` is generated by `kiosk-init` from the app's `/data/apps/feishin/config.json` at start.

**Playback shim:** Feishin already uses the standard `navigator.mediaSession` API for metadata + transport controls. The shim hooks `mediaSession.setActionHandler` for play/pause/next/prev and reads `mediaSession.metadata` for now-playing state. This gives us coordinator integration without any Feishin-internal patching. If `mediaSession` proves insufficient (e.g., no seek position reported), fallback is to inject a small content script that reads from the audio element directly.

**Acceptance criterion:** "Music plays via touchscreen and via hardware buttons; now-playing state appears in `kiosk-playd`; transport controls (play/pause/next/prev) round-trip through hardware buttons → buttond → playd → mediaSession; scrobble state survives reboot." Feature parity with the Electron build is explicitly out of scope.

Tasks:

- [ ] Write `feishin-web_git.bb` recipe: pin upstream SRCREV to a v1.11+ release tag, depend on `nodejs-native` + `pnpm-native`, run `pnpm install --frozen-lockfile && pnpm run build:web`, install `out/web/` to `/usr/share/kiosk-apps/feishin/static/`, install adapted `settings.js.template` to `/usr/share/kiosk-apps/feishin/templates/`
- [ ] Decide HTTP server: prefer extending `kiosk-shell` with a static-file route for app bundles (one server, fewer moving parts) over shipping per-app nginx. Document the decision in `docs/apps/feishin.md`.
- [ ] Write Feishin `app.json` manifest: `port: 9180`, `capabilities: ["playback"]`, `config_dir: "feishin"`, icon, display name
- [ ] Implement `settings.js` generation in `kiosk-init`: read `/data/apps/feishin/config.json`, render template with `SERVER_LOCK=true`, `SERVER_*` from saved config, `ANALYTICS_DISABLED=true`, `FS_GENERAL_THEME=defaultDark`
- [ ] Write Feishin playback shim adapter: hook `navigator.mediaSession.setActionHandler` for play/pause/next/prev/seek; poll `mediaSession.metadata` + audio element for state; emit to `kiosk-playd` over its HTTP/WS API
- [ ] Document web-build feature gaps discovered during integration in `docs/apps/feishin.md` (start from the gap list above; extend with anything found in practice)
- [ ] Set `KIOSK_DEFAULT_APP = "feishin"` in image recipe
- [ ] Build and test: Feishin UI loads in shell iframe at `http://localhost:9180/`, server URL pre-populated and locked, navigation works on touchscreen
- [ ] Test end-to-end playback control: play a track, press F1 to pause, F2/F3 to skip, verify now-playing bar updates and `kiosk-playd` state matches
- [ ] Validate audio formats: confirm Navidrome's default FLAC transcode plays via Chromium HTML5 audio (per Feishin v1.11 changelog); fall back to opus/mp3 transcode if FLAC playback is unreliable on Chromium-on-CM4

### Phase 6: Audio

Web-mode Feishin sends audio through Chromium's HTML5 audio element → Web Audio → PipeWire → ALSA → output device. No MPV in the path (per Phase 5 de-risk). Bit-perfect path concerns documented in the Audio output section apply to Chromium's resampler, not MPV.

- [ ] Add PipeWire + WirePlumber + ALSA to platform image
- [ ] Configure USB audio (USB Audio Class, no extra driver) and HDMI audio outputs as switchable sinks
- [ ] Configure WM8960 reTerminal codec as a tertiary sink (monitoring, not HiFi path)
- [ ] Verify default sink selection: USB DAC if present, else HDMI, else WM8960. Document the priority in `docs/audio.md`.
- [ ] Test playback through Feishin to USB DAC and HDMI
- [ ] Bit-perfect-path validation: feed a known 44.1k/16 WAV through Feishin to USB DAC, capture at DAC input via a USB analyzer (or use a DAC with a sample-rate LED indicator), confirm no resample. If Chromium resamples to 48k, document as known limitation per the "native playback path" follow-up.
- [ ] **At-a-glance signal indicator (LED VU/activity meter).** Front-bezel LEDs are exposed by `dtoverlay=reTerminal` as three `gpio-leds` class devices over an MCP23008 I2C expander: `/sys/class/leds/usr_led0` (USR green), `/sys/class/leds/usr_led1` (STA red), `/sys/class/leds/usr_led2` (STA green). Constraints: on/off only (no real PWM), I2C toggle ceiling ~hundreds of Hz with jitter. Build `kiosk-vumeter`: tap the active PipeWire sink's monitor stream, compute peak over short windows, drive LEDs coarsely. Target resolution: ~16Hz update (each LED toggle decision every ~60ms), enough to resolve 1/16-note pulses at typical tempos and give the user real rhythmic feedback rather than a sustained "on" light. Proposed mapping: STA green = peak above signal-present floor in current window, STA red = peak/clip latched ~200ms, USR green = transport active per coordinator. No smoothing/ballistics, no PWM gradients; the goal is rhythmic confirmation that audio is flowing, not a calibrated meter. Service unit, thresholds configurable in `/etc/kiosk/vumeter.conf`. Rationale: makes "is anything actually coming out?" visible without the screen on, which is the most common HiFi-input-selection failure mode.

### Phase 7: RAUC A/B updates
- [ ] Add meta-rauc to layer stack
- [ ] Add meta-rauc-community/meta-rauc-raspberrypi to layer stack, pin SRCREV to a scarthgap-compatible commit at or after `ce49d53` (2024-06-25, the per-slot-kernel-in-rootfs change)
- [ ] Write wic partition layout (boot 128MB FAT32 + rootfs-a 8GB ext4 + rootfs-b 8GB ext4 + data 14GB ext4), no per-slot kernel files in FAT
- [ ] Configure U-Boot redundant env: `CONFIG_ENV_IS_IN_MMC=y`, `CONFIG_SYS_REDUNDAND_ENVIRONMENT=y`, offsets 0x100000 and 0x200000, size 32K each
- [ ] Write `/etc/fw_env.config` matching the U-Boot env offsets (`/dev/mmcblk0 0x100000 0x8000` and `/dev/mmcblk0 0x200000 0x8000`)
- [ ] Copy and adapt meta-rauc-community's `boot.cmd.in` template: iterate `BOOT_ORDER`, decrement `BOOT_<X>_LEFT` via `setexpr`, set `BOOT_DEV`/`bootargs`/`raucslot`, load `boot/Image` + `boot/dtbs/bcm2711-rpi-cm4.dtb` from the selected rootfs partition, `booti`
- [ ] Ensure `cmdline.txt` on the shared FAT is slot-agnostic (no `root=` -- U-Boot sets that per slot)
- [ ] Write RAUC `system.conf`: `[slot.rootfs.0]` with `bootname=A`, `[slot.rootfs.1]` with `bootname=B`, `bootloader=uboot`
- [ ] Generate signing keys (dev keys for now)
- [ ] Write `rauc-mark-good` systemd service (After= the critical service set: kiosk-shell, kiosk-buttond, kiosk-playd, current app)
- [ ] Configure hardware watchdog: enable `bcm2835_wdt` kernel module, set `RuntimeWatchdogSec=30s` and `RebootWatchdogSec=2min` in `/etc/systemd/system.conf` (per Crash handling section)
- [ ] Verify watchdog behavior: simulate kernel hang (sysrq), confirm reboot within 30s; simulate failed shutdown, confirm forced reboot within 2min
- [ ] Build full image, flash, test A/B update cycle:
  - Install bundle to slot B
  - Reboot into slot B (verify kernel loaded from `/dev/mmcblk0p3:/boot/Image`, not from FAT)
  - mark-good succeeds, `BOOT_B_LEFT` resets to 3
  - Simulate failure: introduce a service that fails on slot B, verify rollback to slot A after 3 attempts
  - Verify slot A's kernel is byte-identical before and after the failed slot B install (proves rootfs-resident kernel is atomic)

### Phase 8: Persistent data
- [ ] Create /data partition mount in fstab
- [ ] Implement bind-mount logic in kiosk-init for /data/platform/* and /data/apps/*
- [ ] Verify app config survives A/B update
- [ ] Verify WiFi credentials persist
- [ ] Verify platform config (kiosk.json) persists

### Phase 9: Update delivery
- [ ] Write kiosk-updater service (polls HTTPS endpoint for version manifest)
- [ ] RAUC D-Bus triggered install from downloaded bundle
- [ ] Test end-to-end: new bundle on server, device downloads, installs, reboots, works

### Phase 10: Polish
- [ ] Boot splash / loading screen (Plymouth or kernel splash)
- [ ] Disable kernel console messages on display
- [ ] Optimize boot time (systemd-analyze, remove unnecessary services)
- [ ] Lock down rootfs (read-only mount, no shell access unless enabled via boot partition flag)
- [ ] Write `docs/` covering: flashing, updates, recovery, app authoring, button + IR mappings, shell API, playback coordinator protocol, playback shim authoring, factory reset gesture, diagnostics, security model, WiFi provisioning.
