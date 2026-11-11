# Upstreaming plan

Ordered by effort against value: the small, high-value items come first.
Items further down depend on people and projects outside this one. Each item
is sent separately, when its owner decides to; nothing here goes out in bulk.

Mobian's bar for listing a device is informal: a kernel branch in
`qcom-linux`, a config in `mobian-recipes`, a droid-juicer config, and someone
keeping it working. The FP4 and FP5 are listed as 3rd tier ("experimental,
demonstration-level"). That's the realistic first target for the FP6. 2nd tier
would need suspend and broader modem testing.

**Images:** this project publishes none. Installable images for others come
from Mobian, once the kernel branch and device config are there. A prebuilt
image would give every phone the same disk encryption key and need a way to
log in without a personal SSH key, and Mobian's release process already deals
with that. Until then, everyone builds their own with `tools/fp6-build.sh`.

## Tier 1: hours each, clear value

| # | Item | Target | Blockers | Talk to |
|---|---|---|---|---|
| 1 | imsd: **SIGTERM before SIGKILL** for the `pw-*` helpers (patch 0004); without it the mic stays open after every call | Catcrafts imsd | none | Catcrafts (Jorijn van der Graaf), via forgejo.catcrafts.net |
| 2 | imsd: **T-Mobile US works** (first US carrier) + the dead-first-P-CSCF report with patch 0002 | Catcrafts imsd, issue + patch | they may prefer the fallback inside the daemon rather than in `ims-pdn-up.sh` | Catcrafts |
| 3 | imsd: call audio targets and channels (patch 0003) | Catcrafts imsd | none | Catcrafts |
| 4 | droid-juicer: `configs/fairphone,fp6.toml` (incl. `modem_pr`), and load the kernel module for the filesystem it mounts (EROFS) | droid-juicer | none | Mobian team (droid-juicer maintainers) |
| 5 | Publish this repository, and a wiki page `InstallingDebianOn/Fairphone/Fairphone6` with the NV-safe install. Mobian's FP5 instructions say `fastboot flash boot`, which on an FP6 wipes the modem NV | this repo; Debian wiki | none: the sources are reworked as listed below | Mobian `#mobian-ports` (Matrix), before the wiki page |

## Tier 2: days each, generic fixes

| # | Item | Target | Blockers | Talk to |
|---|---|---|---|---|
| 6 | `bootloader.sh` `mkbootimg_args`; `packages-base.yaml` `apt-get install` for local debs | mobian-recipes MR | first test whether the FP6 bootloader needs `--os_version` at all; if not, the hook isn't needed for the FP6 | Mobian team |
| 7 | qcom-phone-utils: (a) repack boot after **any** initramfs rebuild (post-update hook); (b) `fp6` → `fairphone/fp6` firmware path and a `qcom/milos` list; (c) `qcom-modem-setup` with no SIM / empty AID; (d) the guard's generic half: write only a slot that holds our image, check the size, read back | qcom-phone-utils (salsa DebianOnMobile-team) | (a), (c), (d) are independent of the FP6 and can go first | DebianOnMobile team |
| 8 | iio-sensor-proxy: no fallback from buffer to poll mode; claim race during libssc discovery | iio-sensor-proxy issues/MRs | write reduced reproductions; Catcrafts found both | iio-sensor-proxy maintainers; credit Catcrafts |
| 9 | Debian bug: the multiarch `libc++.modules.json` has paths that only resolve from `/usr/lib/llvm-22/lib` | Debian BTS, llvm-toolchain-22 | none | LLVM packaging team |
| 10 | `Tested-by` on the FROMLIST series in `milos/` (NT37705 panel, EPH8621 touch, Adreno 810, Iris) on FP6 hardware | linux-arm-msm and subsystem lists | Iris is untested here; only tag what was tested | the series' authors |
| 11 | imsd CMake build (patch 0001), so distributions can build with their own toolchain | Catcrafts imsd | whether they want a second build system next to Crafter.Build | Catcrafts |

## Tier 3: weeks, depends on others

| # | Item | Target | Blockers | Talk to |
|---|---|---|---|---|
| 12 | Kernel: milos branch at 7.3 (or the next LTS) with `milos/`, `catcrafts/`, the clean `milos.config`, and the packaging fixes in `kernel/packaging/` (`openssl` build-dep, failing `binary-arch` loop, Vcs fields; cross builds need `libssl-dev:arm64` installed) | Mobian `qcom-linux` | tiol's 7.2 MR was closed unmerged (reason unknown); most of `catcrafts/` isn't posted upstream; Mobian may want an LTS base | **tiol (Marco Mattiolo) first**, then the Mobian team |
| 13 | `milos-support` package: the device parts of fp6-mobian-support (firmware hook, touch modules, sensor rules, suspend off, echo-cancel, imsd drop-in, AVB tooling) | Mobian `qcom-support` | needs #12; the rework listed in [components/support-package.md](components/support-package.md) | Mobian team |
| 14 | Audio: UCM → alsa-ucm-conf; topology `.m4` → linux-msm audioreach-topology → binary in linux-firmware → Debian firmware packages | upstream projects | Catcrafts wrote them: they send them, or OK us sending them; needs the WCD9378 driver upstream for the mic | Catcrafts; linux-msm |
| 15 | Kernel: post the `catcrafts/` patches (WCD9378, IMX896/DW9784, CAMSS C-PHY, sensors, NFC, suspend fixes) | Linux | their work, their call | Catcrafts; David Heidelberg (C-PHY series) |
| 16 | Kernel: the two WIP sound DT patches in `milos/` | Linux | not posted | Luca Weiss (Fairphone) |
| 17 | imsd in Debian: ITP, then upload | Debian (Section net) | items 1–3 and 11 settled upstream; needs a sponsor | Debian Mobile team |

## Tier 4: long tail

| Item | Target | Note |
|---|---|---|
| 5 GHz WiFi: extract the FP6 board data (`bdwlan`) from vendor and submit a `board-2.bin` | ath11k board files → linux-firmware | |
| GPS: Catcrafts' ModemManager patches (AFW client unlock, position report → NMEA) | ModemManager (draft MR !1463) | |
| 5G SA data, the ModemManager crash during bring-up | ModemManager | try 1.25.x first |
| SMS over IP in imsd, so 5G SA can carry SMS and `fp6-lte-pin` can go | Catcrafts imsd | |
| libcamera: IMX896/OV13B10 helpers, softISP AF, AWB clamp (16 patches) | libcamera | some already proposed by others |
| Snapshot opens the new camera before closing the old one | GNOME Snapshot / PipeWire libcamera plugin | inferred; confirm the cause first |
| Front camera S5KKD1 driver | Linux | new driver; Fairphone may have documentation |
| Suspend: UFS resume on milos, WCN6755 reset on idle | Linux (UFS, ath11k) | |
| battmgr: input current limit stuck at 100 mA on a PC port | Linux (`qcom_battmgr`, gadget → battmgr) | `qcom-battmgr-usb/input_current_limit` reads 100000 (µA): mainline never tells battmgr the gadget is configured, and the property is read-only in `qcom_battmgr.c`. Fix: make `USB_INPUT_CURR_LIMIT` writable, or forward `usb_gadget_vbus_draw` to battmgr (500 mA) |
| Side switch (`SW_MUTE_DEVICE`) → a user-chosen action (mute, DND, airplane mode) | Phosh / feedbackd | |
| Fingerprint (fingerprintd), NFC userspace | packaging | check licences first |
