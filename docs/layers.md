# Upstream Layers

Pinned versions of all upstream Yocto layers used by the project. All commits are branch HEADs as of 2026-05-25.

## Pinned versions

| Layer | Branch | Commit | Date | Source |
|---|---|---|---|---|
| **poky** | scarthgap | `d4576e3c081a7ee7…` | 2026-05-20 | git.yoctoproject.org |
| **meta-openembedded** | scarthgap | `ae7dfb12245c7f9b…` | 2026-05-05 | git.openembedded.org |
| **meta-browser** | scarthgap | `85eeb6b50883d22c…` | 2026-05-06 | OSSystems/meta-browser |
| **meta-rauc** | scarthgap | `d63878f20eba7a85…` | 2026-04-07 | rauc/meta-rauc |
| **meta-clang** | scarthgap | `5bce7e26a38a58bb…` | 2026-03-16 | kraj/meta-clang |
| **meta-raspberrypi** | scarthgap | `2c646d29912dcc87…` | 2025-12-19 | git.yoctoproject.org |
| **meta-seeed-cm4** | main | `a2f9438ee3d2e16b…` | 2025-11-20 | Seeed-Studio/meta-seeed-cm4 |
| **meta-rauc-community** | scarthgap | `222c61275054974c…` | 2025-11-04 | rauc/meta-rauc-community |
| **meta-lts-mixins** (rust) | scarthgap/rust | `c19b6da5a3afd3c8…` | — | git.yoctoproject.org |
| **meta-lts-mixins** (u-boot) | scarthgap/u-boot | `a44882db02a0ed0f…` | — | git.yoctoproject.org |

Full commit hashes are in `kas/reterminal-hifi.yml`.

## Yocto release constraint

This project is pinned to **Yocto scarthgap (5.0 LTS)**, supported through **April 2028**.

The binding constraint is **meta-seeed-cm4**. This layer provides `MACHINE=seeed-reterminal` — the BSP for the reTerminal's DSI display, touchscreen, buttons, and light sensor. It is maintained by Seeed (the hardware vendor), has no Yocto release branches (only `main`), and declares:

```
LAYERSERIES_COMPAT_meta-reterminal = "scarthgap"
```

Seeed's commit cadence is driven by new board variants, not Yocto releases. There is no indication that whinlatter or wrynose support is planned.

All other upstream layers track scarthgap via dedicated branches and are actively maintained.

## Upgrade path

When moving to a newer Yocto release becomes necessary, the options are:

1. **Fork meta-seeed-cm4** and port it (update `LAYERSERIES_COMPAT`, fix any recipe API changes). Likely minimal work — the layer is mostly DT overlays and kernel config fragments.
2. **Wait for Seeed** to add newer compat. Unlikely to happen quickly given their commit cadence.
3. **Write a standalone reTerminal BSP** using `meta-raspberrypi` as the base, adding the reTerminal-specific DT overlays, touchscreen driver, and button GPIO config. More effort upfront but removes the vendor dependency entirely.

Option 1 is the practical path. Option 3 is worth considering if we need to diverge significantly from Seeed's kernel or devicetree choices.
