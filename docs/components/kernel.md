# Kernel

**Package:** `linux-image-7.3-milos` (source `linux-7.3-milos`)
**Upstream target:** Mobian `Mobian-team/devices/kernels/qcom-linux`, as a milos
branch next to the existing `mobian-sc7280-*` (FP5) branches. Individual
patches go to Linux through their authors.
**Licence:** GPL-2.0 (kernel). Patches keep their authors' copyright.

## What it is

Linux v7.3 from kernel.org with four patch directories, in the layout Mobian's
`qcom-linux` packaging already uses (`debian/patches/<origin>/`):

| Directory | Count | Source |
|---|---|---|
| `milos/` | 32 | [milos-mainline] tag `v7.3.0-milos` (commit `939a2ad2`): 40 commits on v7.3, minus 8 empty separator commits. Mostly `FROMGIT` (queued for 7.4/7.5) and `FROMLIST` (panel, touch, GPU, Iris, q6apm) |
| `catcrafts/` | 72 | [Catcrafts milos-linux] branch `combined-stable` (commit `27825d9f`), linearized. Microphone codec WCD9378, main camera IMX896 + DW9784 + CAMSS C-PHY (incl. 9 patches by David Heidelberg), OV13B10 and milos CAMSS (5 by nondescriptpointer), IMU/barometer/light/magnetometer variants, NFC S3NRN4V, UFS and GENI suspend fixes, qrtr HELLO (Joonhoe Kim), pmic_glink, BT wake level, ramoops |
| `debian/` | 1 | regdb certificates, from Mobian's `wip/tiol/7.2-milos` |
| `mobian/` | 1 | disable the in-kernel PD mapper, from the same branch |

**This repository adds no kernel code.** What it adds is:
1. the 7.3 rebase of Mobian's milos packaging (tiol's branch was on 7.2),
2. a faithful linearization of Catcrafts' merge-based tree into a quilt
   series,
3. a rewritten `milos.config` fragment,
4. on-device testing of the result.

### Why 7.3 and not 7.2

7.2's milos queue wires a downstream ESWIN touch driver in unconditionally;
7.3 carries the EPH8621 v3 driver that is on its way upstream. The FP6 device
tree, `milos-fairphone-fp6.dts`, is upstream, and Mobian already has a
`mobian-sc7280-7.3` branch for the FP5.

## Linearization

`combined-stable` is a merge of topic branches. It was rebuilt commit by commit,
merges included, from the forge's per-commit patches. It was checked to be identical to the
forge's `v7.3.0-milos...combined-stable` diff, then rebased into a linear
series. Three DTS patches needed their hunks re-placed, because topic branches
add nodes at the same spot of `milos-fairphone-fp6.dts` (the content is
unchanged; only the position moved): the WCD9378 codec node, the sensor I²C bus, and the
VL53L3 ToF node.

Verification chain, each step byte-identical:
1. kernel.org v7.3 + `milos/` == the milos-mainline `v7.3.0-milos` tarball
   (sha512 pinned by postmarketOS)
2. … + `catcrafts/` == the Catcrafts `combined-stable` tree
3. … + `debian/` + `mobian/` == exactly those two deltas

The whole series applies with `patch -p1 -F0`, as `dpkg-source` 3.0 (quilt)
does: no binary, rename or mode-change hunks. Tooling:
`tools/export-catcrafts-series.sh`, `tools/catcrafts-order.py`,
`tools/replicate-graph.py`, `tools/splice-ref.py`.

### Rebuilding the series from upstream

The patches aren't stored in this repository. `kernel/regen.sh` fetches each
upstream commit as a patch (`kernel/upstream.txt`, in series order), applies
them with `git am` on kernel.org's v7.3, regenerates the series with
`git format-patch`, and checks every patch against `kernel/patches.sha256`
(without its first line, which carries a commit id). It then assembles the
source package: `qcom-linux` at tiol's pinned commit, `kernel/packaging/*.patch`,
`milos.config`, `README.milos-linux` and the series.

The rebase that linearized `combined-stable` resolved five Catcrafts patches by
context: the three re-placed DTS hunks above, plus "add IMU" and "reserve a
ramoops region", whose context differs at that point of the linear series.
Upstream's version of those doesn't apply with `git am`, so `kernel/fixups/`
holds a diff from each upstream patch to the published one (hunk positions and
context lines only). `kernel/make-fixups.sh` recomputes them after a resync.

## Config fragment (`milos.config`)

Mobian builds kernels from layered fragments (`debian.config` →
`debian.arm64.config` → `mobian.config` → `<soc>.config`) plus `olddefconfig`.
tiol's `milos.config` was a 574-line defconfig dump. Measured against the lower
layers, 134 lines were redundant and 221 overrode a Debian/Mobian choice.
Among the overrides:

- **`# CONFIG_RD_ZSTD is not set`** (all compressors but gzip were off).
  Debian's initramfs-tools defaults to zstd, so that kernel couldn't unpack its
  own initramfs. **Boot blocker.**
- `PANIC_TIMEOUT`, `FTRACE`, `DEVMEM`, `IOSCHED_BFQ`, `UEVENT_HELPER` and
  `DEVTMPFS_MOUNT` on, `DEBUG_INFO_REDUCED` on, `FW_LOADER_COMPRESS_XZ` off,
  `MMC_BLOCK_MINORS` 32, and others changed for no FP6 reason.
- Options the FP6 doesn't need: WLED, Goodix and RMI4 touch,
  devfreq governors, `THERMAL_EMULATION`, `UFS_BSG`.
- `WCD938X_SDW`: the FP6 has no WCD938x; its microphone codec is the WCD9378.

The rewrite is a 75-symbol device-delta fragment in the style of `sc7280.config`:
clocks and I²C built in, drivers as modules. Three non-obvious lines:

- `MEDIA_PLATFORM_SUPPORT=y`: with `EXPERT=n`, `MEDIA_SUPPORT_FILTER` silently
  drops CAMSS and Iris otherwise.
- `BLK_INLINE_ENCRYPTION`, `SCSI_UFS_CRYPTO`, `FS_ENCRYPTION_INLINE_CRYPT`: off
  in the base layers. Without them the UFS inline crypto engine isn't built,
  its supplier `sync_state` never fires, and power domains stay on. FP5 hit
  the same problem (qcom-linux issue #60).
- `SND_SOC_WCD9378_SDW`, `VIDEO_IMX896`, `VIDEO_DW9784`, `QMC6308`,
  `HW_RANDOM_QCOM` for the Catcrafts drivers.

`EROFS_FS` stays a module. droid-juicer needs it (the vendor partition is EROFS);
see [firmware.md](firmware.md).

`PCI=n` is safe: WiFi is on AHB, the FP6 device tree has no PCIe controller,
and Catcrafts' kernel runs without PCI too. imsd needs `INET6_ESP` and
`XFRM_USER` for its IPsec security associations; the fragment doesn't set
them, because Debian's base layers already build them.

Validation: `tools/run-olddefconfig.sh` resolves the layers in a network-less
container (`tools/Containerfile.kconfig`, Debian's aarch64 gcc), and
`tools/fragcheck.py` compares requested with resolved values: 75/75 kept.
`tools/dt-driver-check.py` maps every compatible in the FP6/Milos DT to its
driver's Kconfig symbol: 187 covered, the rest explained (QCE disabled in the DT,
VL53L1X left off as Catcrafts does, nodes without drivers).

### Policy differences from Catcrafts' kernel, as tested

- **PD mapper:** Mobian disables the in-kernel one (`mobian/0049`,
  `QCOM_PD_MAPPER` unset) and runs the userspace `pd-mapper`. On the FP6 that
  works: all four remoteprocs and audio come up.
- **`QRTR=m`** works. tiol's fragment had `QRTR=y`, maybe on purpose: the FP5
  lost the DSP's first QRTR HELLO with qrtr as a module. `catcrafts/` carries a
  related qrtr fix. Whether that fix is what makes the module safe here hasn't
  been isolated.
- **Open:** Catcrafts' running config also enables `QRTR_TUN`, `QCOMTEE` and
  `RPMSG_CHAR`/`RPMSG_CTRL`. Nothing here has needed them so far; their
  userspace may.

## Packaging

Based on tiol's `wip/tiol/7.2-milos` (commit `7a3790b`), as four commits in
`kernel/packaging/`:

| Change | Why |
|---|---|
| update to 7.3: `KVER`, package names, `gbp.conf` branches, `watch`, changelog | |
| `openssl:native` in Build-Depends | the build runs `openssl`; it failed in a clean chroot |
| `set -e` in the `binary-arch` loop | the loop runs in one shell, so failed steps still produced packages |
| `control.in`: Homepage and Vcs point to `qcom-linux` | the template expanded to a `milos-linux` repository that doesn't exist (tiol's generated `control` was already right) |

Cross builds need `libssl-dev:arm64`: the headers package builds its
`scripts/` tools for arm64, and `sign-file` links OpenSSL. The build in
[../reproduce.md](../reproduce.md) passes `-d`, which skips the
build-dependency check, so `tools/Containerfile.debbuild` installs it. With
it, every binary in the headers package (`sign-file`, `modpost`, `fixdep` and
the rest) is arm64. Building a module on the phone against it is untested.
The phone runs `7.3-1~fp6test1`, built from the same series and config before
these packaging changes.

## Tested

Daily use since the first boot: everything in the status matrix in
[../overview.md](../overview.md). One kernel update cycle (reinstall →
boot image rewritten → boots).

## Before Mobian can take it

- tiol's MR !58 for 7.2 was closed unmerged. **Talk to tiol first**, so the
  effort isn't forked.
- 72 Catcrafts patches are mostly not posted upstream. Mobian says it doesn't
  package heavily device-specific kernels, so the more of `catcrafts/` reaches
  the lists, the easier the MR. The audio parts matter most (no microphone without them).
- Mobian may want an LTS base rather than 7.3.

[milos-mainline]: https://github.com/milos-mainline/linux
[Catcrafts milos-linux]: https://forgejo.catcrafts.net/Catcrafts/milos-linux
