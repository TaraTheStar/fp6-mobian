# Overview

## Hardware status

Tested on a Murena-sold Fairphone (Gen. 6) shipped with /e/OS 4.4.2. The
bootloader is unlocked, and Mobian forky with Phosh runs from internal storage
under full-disk encryption. Carrier: T-Mobile US.
Software: kernel `7.3-milos`, ModemManager 1.24.2 (Debian), imsd 1.1.0 with
the patches described in [components/modem-and-volte.md](components/modem-and-volte.md).

### Works

| Area | Notes |
|---|---|
| Display | Novatek NT37705 panel, DSI. A few harmless DPU "invalid DSPP" log lines |
| Touch | ESWIN EPH8621. Also in the initramfs, so the unl0kr passphrase prompt works. One `-22` read error at probe is harmless |
| GPU | Adreno 810. Phosh is smooth |
| Buttons, backlight | Power, volume, brightness slider. Phosh's "EPROTO writing brightness" log line is harmless |
| USB networking | `mobile-usb-networking`, phone at 10.66.0.1, SSH |
| Full-disk encryption | LUKS2 root, unl0kr touch prompt; a second LUKS volume (e.g. `/home` on microSD) chain-unlocks with a keyfile |
| Speakers | 2× AW88261 |
| Microphone | Bottom mic (AMIC1) through the WCD9378 codec |
| Sensors | Accelerometer/gyro (ICM-42631), magnetometer (QMC6308), barometer (SPL07-003) and light/proximity (STK36C61) all probe and show up in IIO. Per-sensor behaviour in Phosh (auto-rotate, proximity in calls) hasn't been checked one by one yet |
| Rear cameras | Main IMX896 and ultra-wide OV13B10 via libcamera and PipeWire, 720p and 1080p |
| Battery | Level and charging via battmgr |
| Haptics | Vibration works, including key-press feedback in the unl0kr passphrase prompt |
| Remote processors | adsp, cdsp, modem, wpss all running. Mobian's userspace pd-mapper is enough; the in-kernel one is not needed |
| Mobile data | LTE, IPv6 plus 464XLAT for IPv4 |
| SMS, MMS | Both directions on LTE (mmsd-tng + Chatty for MMS) |
| VoLTE calls | Both directions, AMR-WB, via imsd and GNOME Calls. No late or dropped frames. An incoming call rings with the screen off and locked: the phone never suspends, so there is nothing to wake |
| Kernel updates | `apt` installs a new kernel → the boot image is rebuilt and written from Linux, then read back and verified |
| Crash logs | ramoops: the previous boot's kernel log is in `/var/lib/systemd/pstore/` |

### Works with limits

| Area | Limit |
|---|---|
| WiFi | 2.4 GHz only. ath11k uses generic board data; the FP6's own `board-2.bin` isn't in linux-firmware |
| Bluetooth | Controller powers up. Pairing and audio untested |
| Call audio | Earpiece only, through WebRTC echo cancellation. A slight echo remains for the far end |
| VoLTE after boot | If the first P-CSCF the network offers is dead, registration takes about 2 minutes (one failed attempt, then the next P-CSCF) |
| Cameras | No autofocus and no sensor tuning in Debian's libcamera 0.7.2, so images are soft and exposure is weak. GNOME Snapshot shows a black screen when switching cameras. Confirmed: the ultra-wide fails to preroll while the main camera streams. Inferred, not confirmed: Snapshot opens the new camera before closing the old one |
| Charging from a PC port | Input stays capped at 100 mA on a plain USB port: mainline never tells the battery firmware (battmgr) that the USB gadget is configured. The phone discharges while it says "charging". Use a wall charger |
| Charge limit | Charging stops at 70–80 %, set by the battery firmware |
| SMS | Once, the first SMS sent after boot failed and the retry worked. Not reproduced |
| ModemManager | 1.24.2 segfaulted three times while the IMS bearer and mobile data came up together. Not seen once both are up |
| Side switch | GPIO 107 in `gpio-keys`, reported as `EV_SW`/`SW_MUTE_DEVICE`. It's an ordinary switch, not a hardware kill switch, and nothing in Phosh acts on it yet |

### Doesn't work

| Area | Why |
|---|---|
| Front camera | Samsung S5KKD1: no driver exists |
| 5G SA (T-Mobile US) | Registers packet-only: no SMS path (imsd doesn't do SMS over IP), and data stalls. The modem is kept on LTE ([fp6-lte-pin](components/modem-and-volte.md#fp6-lte-pin)) |
| 5 GHz WiFi | Board data, see above |
| GPS | Needs ModemManager patches (Catcrafts carries them; upstream MR in draft) |
| Suspend | Disabled on purpose: UFS resume has a reported root filesystem loss on Milos, and idle suspend resets the WiFi/BT firmware, after which WiFi stays down for about 40 minutes |

### Untested

Fingerprint (needs Catcrafts' fingerprintd, and the focal64 trustlet
extracted), NFC (kernel driver present, no userspace), eSIM management (lpac),
video decoding (Iris), Wi-Fi calling, USB-C audio and display, Plasma
Mobile (imsd-plasma is built but unused), Catcrafts' `fp6-charging-mode` (for
the 70–80 % charge limit) and `callaudioshim`, **emergency calls**, and any
carrier other than T-Mobile US with this Debian build of imsd. Catcrafts has
verified VoLTE with imsd on several European carriers on their own image.

## How the pieces fit

```
                        ┌────────────────────────── host ───────────────────────────┐
kernel.org v7.3 ─┐      │                                                           │
milos-mainline ──┼─► kernel series + milos.config ─► linux-image-7.3-milos (.deb)    │
Catcrafts tree ──┘      │                                         │                 │
                        │  fp6-mobian-support (.deb) ─────────────┤                 │
Catcrafts imsd ───────► │  imsd, imsd-ofono (.deb) ───────────────┤                 │
                        │                                         ▼                 │
mobian-recipes ───────► │  qcom-wip target + FP6 config ──► rootfs + boot image     │
droid-juicer config ──► │                                                           │
                        └───────────────────────────────────────────────────────────┘
                                                    │
                        ┌────────────────────── phone ──────────────────────────────┐
                        │ first boot: droid-juicer copies firmware from the stock   │
                        │ vendor/modem/bluetooth partitions → initramfs rebuilt →   │
                        │ boot image rewritten from Linux (guarded) → reboot        │
                        └───────────────────────────────────────────────────────────┘
```

- **Kernel** ([components/kernel.md](components/kernel.md)): Linux 7.3,
  the milos-mainline patches (mostly on their way upstream), and the Catcrafts
  tree (microphone, cameras, sensors, NFC, suspend fixes). Packaged with
  Mobian's `qcom-linux` packaging.
- **Boot** ([components/boot-and-avb.md](components/boot-and-avb.md)): the
  FP6 bootloader has two traps, the NV erase on `fastboot flash boot` and AVB
  chaining on `boot`. Everything here writes `boot` from Linux, through a
  guard that checks the AVB data first.
- **Firmware** ([components/firmware.md](components/firmware.md)):
  droid-juicer extracts it on the phone. `modem.mbn` is too large for the boot
  partition, so the modem starts after the root filesystem is up.
- **Device glue** ([components/support-package.md](components/support-package.md)):
  one package, `fp6-mobian-support`, collects the guard, the hooks, the
  audio and sensor configuration and the modem workarounds.
- **VoLTE** ([components/modem-and-volte.md](components/modem-and-volte.md)):
  the FP6 modem doesn't run IMS for mainline Linux, so imsd does it on the
  host. It's packaged here with the Debian toolchain only.
- **Audio** ([components/audio.md](components/audio.md)),
  **sensors and cameras** ([components/sensors-and-cameras.md](components/sensors-and-cameras.md)),
  **image** ([components/image-recipes.md](components/image-recipes.md)),
  **tools** ([components/tools.md](components/tools.md)).

## Hardware reference

| Part | Chip | Kernel driver |
|---|---|---|
| SoC | Qualcomm SM7635 (Milos) | `qcom/milos.dtsi` |
| Panel | Novatek NT37705 | `panel-novatek-nt37705` |
| Touch | ESWIN EPH8621 (SPI) | `eswin_eph8621` |
| GPU | Adreno 810 | `msm` |
| WiFi/BT | WCN6755 | `ath11k_ahb`, `hci_qca` |
| Speakers | 2× Awinic AW88261 | `snd-soc-aw88261` |
| Mic codec | Qualcomm WCD9378 (SoundWire) | `snd-soc-wcd9378` (Catcrafts) |
| Main camera | Sony IMX896 (C-PHY) + DW9784 OIS/AF | `imx896`, `dw9784` (Catcrafts) |
| Ultra-wide | OmniVision OV13B10 | `ov13b10` |
| Front camera | Samsung S5KKD1 | none |
| IMU | TDK ICM-42631 | `inv-icm42600-spi` |
| Magnetometer | QST QMC6308 | `qmc6308` |
| Barometer | Goertek SPL07-003 | `dps310` (Catcrafts) |
| Light/proximity | Sensortek STK36C61 | `stk3310` (Catcrafts) |
| NFC | Samsung S3NRN4V | `s3fwrn5` (Catcrafts) |
| Storage | UFS | `ufs-qcom` |
