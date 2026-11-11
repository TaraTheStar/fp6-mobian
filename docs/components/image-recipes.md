# Image recipes

**Base:** [mobian-recipes] (commit `a4fff86`), using its `qcom-wip` target. That
target exists for out-of-tree ports: it installs local `.deb`s from
`devices/qcom/packages/` and a droid-juicer config overlay, and reads the device
parameters from `devices/qcom/configs/wip.toml`.
**Upstream target:** mobian-recipes (`milos.toml`, the `bootloader.sh` hook, the
`packages-base.yaml` change). The droid-juicer config goes to droid-juicer.

## Changes

Four commits in `patches/mobian-recipes/`, on upstream `a4fff86`:

| Patch | Change | Upstream? |
|---|---|---|
| 0001 | `devices/qcom/bootloader.sh`: optional per-device `mkbootimg_args` key, passed through to `mkbootimg` | yes: small and generic |
| 0002 | `devices/qcom/packages-base.yaml`: `apt-get install /srv/*.deb` instead of `dpkg -i`: local debs may pull dependencies that aren't in the image yet (imsd needs `libc++1`) | yes, generic for `qcom-wip` |
| 0003 | `devices/qcom/configs/milos.toml` and `"milos"` in `build.sh`'s qcom case: FP6 parameters (chipset `milos`, header v2, page 4096, mkbootimg's default base 0x10000000, kernel 0x8000, ramdisk 0x1000000, DTB 0x01f00000, tags 0x100; vendor `fairphone`, model `fp6`), the same layout as `sc7280.toml` (FP5) | yes, once a milos kernel is in the archive; untested until then |
| 0004 | `devices/qcom/configs/wip.toml` with the same parameters plus the debug `append` line, and `build-fp6.sh`, a wrapper for `build.sh -t qcom-wip -e phosh -s -H fp6-mobian` that checks the debs, the droid-juicer config and an SSH key are in place | no, local builds |

`userdata` has 4096-byte sectors. mobian-recipes already derives the image's
sector size from the 4096 page size, so that needs no change.

The droid-juicer config (`devices/qcom/droid-juicer/fairphone,fp6.toml` in the
image) comes from `patches/droid-juicer/`; it goes to droid-juicer, see
[firmware.md](firmware.md).

The `--os_version 99.87.36 --os_patch_level 2099-12-31` arguments copy what
postmarketOS passes for the FP6. Whether the bootloader needs them is untested,
so they stay until someone proves otherwise.

## Build

See [../reproduce.md](../reproduce.md#14-image). Built in
`tools/Containerfile.debos` (`godebos/debos` + `yq`, `img2simg`, `bmaptool`,
`cryptsetup`) with `/dev/kvm` passed through. About 70 minutes.

## What the built image contains

The image has been inspected offline:
- the three local debs (kernel, fp6-mobian-support, imsd + imsd-ofono), with `libc++1` pulled in;
- droid-juicer 0.4.3 with the FP6 config, including `modem_pr`;
- `qbootctl.service` enabled (marks the slot successful);
- `x-systemd.growfs` on `/`;
- the user's SSH key (from `overlays/ssh/authorized_keys`) and the default credentials.

Built images contain your SSH key and, after first boot, extracted firmware.
**Don't publish built images.**

## Before upstream

0001–0003 can go as one merge request, after checking whether the FP6
bootloader needs the `--os_version` arguments at all.

[mobian-recipes]: https://salsa.debian.org/Mobian-team/mobian-recipes
