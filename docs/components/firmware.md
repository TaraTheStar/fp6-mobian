# Firmware

**Lives in:**
- the droid-juicer config `fairphone,fp6.toml`: `patches/droid-juicer/`, a
  commit for droid-juicer's `configs/`; in the image via mobian-recipes'
  `devices/qcom/droid-juicer/`;
- in `fp6-mobian-support`: the initramfs hook `fp6-firmware`, the droid-juicer drop-in
  `droid-juicer.service.d/fp6.conf`, `fp6-remoteproc-start` and its service.

**Origin:** written for this port. File lists from postmarketOS'
`device-fairphone-fp6` and the kernel's DT firmware names.
**Licence:** scripts GPL-3.0-or-later, droid-juicer config MIT (droid-juicer's licence). The firmware itself is proprietary
and **never distributed**: droid-juicer copies it from the phone's own stock
partitions on first boot.
**Upstream target:** droid-juicer (`configs/fairphone,fp6.toml`, plus the EROFS fix),
qcom-phone-utils (initramfs hook, `qcom/milos` case).

## What droid-juicer extracts

All files go to `/lib/firmware/updates/`.

| From | Files | To |
|---|---|---|
| `vendor` `firmware/` | `gen80300_zap.mbn`, `vpu20_2v.mbn`, `aw882xx_acf.bin` (renamed `aw88261_acf.bin`) | `qcom/milos/fairphone/fp6/` |
| `vendor` `firmware/` | `gen80300_gmu.bin`, `gen80300_sqe.fw` | `qcom/` |
| `modem` `image/` | adsp, adsp_dtb, cdsp, cdsp_dtb, ipa_fws, modem (`.mdt` + segments), `*.jsn` | `qcom/milos/fairphone/fp6/` |
| `modem` `image/qca6750/` | `wpss.mdt` | `qcom/milos/fairphone/fp6/` |
| `bluetooth` `image/` | `msbtfw12.mbn`, `msnv12.bin` | `qca/` |
| `modem` folder `image/modem_pr/` | 172 files: mcfg MBNs and RF configs | `qcom/milos/fairphone/fp6/modem_pr/` |

**`modem_pr` is required.** Without it the modem remoteproc runs, but the modem
stays `offline` and refuses to enable ("Invalid transition"). It asks
tqftpserv for `/readonly/firmware/image/modem_pr/...`. It uses droid-juicer's
`folders` key (supported by droid-juicer 0.4.3, the version in forky).

## EROFS

The FP6's `vendor` partition is EROFS. `mount(2)` doesn't autoload the module, so
droid-juicer's mount fails with `EINVAL` on first boot. The drop-in adds
`ExecStartPre=-/usr/sbin/modprobe erofs`. **Generic fix:** droid-juicer should
load the module for the filesystem type it's about to mount. The alternative,
`EROFS_FS=y`, only fixes kernels whose config someone remembers to change.

## Initramfs hook (`fp6-firmware`)

Remoteprocs that probe from the initramfs don't retry a missing firmware later,
so the firmware has to be in the initramfs.

qcom-phone-utils' `qcom-firmware` hook has no FP6 case. It would look in
`qcom/milos/fp6/`, while the DT asks for `qcom/milos/fairphone/fp6/`. Our hook
adds the FP6 list and skips missing files, which is normal before droid-juicer
has run.

It also adds the touchscreen modules (`eswin_eph8621 spi-geni-qcom gpi`), so the
unl0kr passphrase prompt accepts touch input. It adds them **unconditionally**: the
hook also runs in the image build chroot, where `/proc/cmdline` is the build
host's, and an earlier conditional version left them out of the image.

## `modem.mbn` stays out of the initramfs

`modem.mbn` is 112.6 MB uncompressed (about 51 MB compressed). With it, the boot image is
about 109 MB, more than the 96 MiB partition. Without it, the modem remoteproc
probed in the initramfs can't boot.

`fp6-remoteproc-start.service` runs after `local-fs.target`, `rmtfs` and
`tqftpserv`, and before ModemManager. For each remoteproc that is `offline`
and whose firmware file exists under `/lib/firmware` (plain, `.zst` or `.xz`),
it writes `start` to its `state`. The modem is up about 3 seconds later.

## Tested

- First boot on microSD and on internal storage: all files extracted, including the
  172 `modem_pr` files. The guard then wrote a boot image with a 43.6 MiB
  initramfs.
- All four remoteprocs `running` on every boot since.

## Rework before upstream

- droid-juicer: send the config, and fix the fs-type module loading in droid-juicer
  itself; then drop our drop-in.
- qcom-phone-utils: an `fp6` → `fairphone/fp6` mapping and a `qcom/milos` list,
  minus `modem.mbn`. The touch modules belong in a milos-support package, or in a
  generic "input devices for unl0kr" hook.
- `fp6-remoteproc-start` is a workaround. Better: the remoteproc core retrying
  firmware loads once the root filesystem is mounted, or Mobian's split
  between initramfs and rootfs firmware handling this generally.
- WLAN board data (`board-2.bin` for 5 GHz) is not extracted yet; see
  [../upstreaming.md](../upstreaming.md).
