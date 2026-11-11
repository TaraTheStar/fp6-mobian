# fp6-mobian-support

**Package:** `fp6-mobian-support`, `Architecture: all`, version `0.1`, a native
source package in `packaging/fp6-mobian-support/` (files grouped by component:
`boot/`, `firmware/`, `audio/`, `sensors/`, `modem/`, `system/`).
**Depends:** qcom-support-common, qcom-phone-utils, qbootctl, mkbootimg,
initramfs-tools, modemmanager, libglib2.0-bin.
**Licence:** our files GPL-3.0-or-later; Catcrafts' files as listed below.
**Upstream target:** split up; see the table. Most of it belongs in a
`milos-support` binary package from Mobian's `qcom-support`, the way other
SoCs get `<soc>-support`.

The package collects all the device glue. Each file and the reason for it:

| File | Purpose | Origin | Notes |
|---|---|---|---|
| `/etc/kernel/postinst.d/zz-qcom-bootimg` (+ divert) | boot write guard: a symlink to `/usr/lib/fp6-mobian-support/zz-qcom-bootimg` | ours | [boot-and-avb.md](boot-and-avb.md) |
| `/usr/lib/fp6-mobian-support/boot-is-mobian` | does the active slot hold Mobian? | ours | heuristic |
| `/usr/lib/fp6-mobian-support/fp6-boot-avb` | AVB check, maxsize, relocate | ours | FP6-specific |
| `/usr/lib/fp6-mobian-support/fp6-reboot` | droid-juicer reboot → fastboot while RAM-boot testing | ours | test-path only |
| `/usr/sbin/fp6-make-bootimg` | build a boot image without writing it | ours | |
| `/usr/share/initramfs/post-update.d/zz-fp6-bootimg` | repack boot after any initramfs rebuild | ours | **generic Mobian gap** |
| `/usr/share/initramfs-tools/hooks/fp6-firmware` | FP6 firmware + touch modules into the initramfs | ours | [firmware.md](firmware.md) |
| `/usr/lib/systemd/system/droid-juicer.service.d/fp6.conf` | `modprobe erofs`; `fp6-reboot` | ours | the erofs part is generic |
| `/usr/lib/fp6-mobian-support/fp6-remoteproc-start` + `.service` | start the modem once the rootfs is up | ours | workaround |
| `/usr/lib/fp6-mobian-support/fp6-lte-pin` + `.service`, `/etc/default/fp6-lte-pin` | keep the modem on LTE | ours | carrier workaround, [modem-and-volte.md](modem-and-volte.md#fp6-lte-pin) |
| `/usr/lib/systemd/system/imsd.service.d/fp6-audio.conf` | call audio routing and level for imsd | ours | needs imsd patch 0003 |
| `/etc/apt/preferences.d/fp6-no-distro-kernels.pref` | pin Debian/Mobian `linux-image-*` to −1 | ours | until Mobian ships a milos kernel |
| `/usr/lib/systemd/sleep.conf.d/50-fp6-no-suspend.conf` | no suspend/hibernate | ours | see [../overview.md](../overview.md) |
| `/usr/share/alsa/ucm2/conf.d/milos/MILOS-Fairphone-Gen6.conf`, `/usr/share/alsa/ucm2/Fairphone/fp6/HiFi.conf` | UCM | Catcrafts fp6-img `41f6fb4`, verbatim, BSD-3-Clause | [audio.md](audio.md) |
| `/usr/lib/firmware/qcom/milos/MILOS-Fairphone-Gen6-tplg.bin` | AudioReach topology | built from Catcrafts' audioreach-topology source, BSD-3-Clause | [audio.md](audio.md) |
| `/usr/share/pipewire/pipewire.conf.d/50-fp6-echo-cancel.conf` | WebRTC echo canceller for calls | Catcrafts fp6-img `41f6fb4`, **modified**, BSD-3-Clause | [audio.md](audio.md) |
| `/usr/lib/udev/rules.d/81-fp6-accel-poll.rules` | force iio-sensor-proxy to poll the accelerometer | Catcrafts fp6-img `41f6fb4` (fp6-device-tweaks), verbatim, **GPL-3.0-only** | [sensors-and-cameras.md](sensors-and-cameras.md) |
| `/usr/lib/udev/rules.d/91-fp6-no-ssc-sensors.rules` | drop libssc tags (no SSC on this image) | Catcrafts fp6-img `41f6fb4` (fp6-device-tweaks), verbatim, **GPL-3.0-only** | same |
| `/usr/lib/systemd/system/iio-sensor-proxy.service.d/fp6-restart.conf` | restart iio-sensor-proxy on failure | Catcrafts fp6-img `41f6fb4` (fp6-device-tweaks), verbatim, **GPL-3.0-only** | same |
| `/usr/lib/modules-load.d/fp6-imu.conf` | load `inv-icm42600-spi` | Catcrafts fp6-img `41f6fb4` (fp6-device-tweaks), verbatim, **GPL-3.0-only** | same |

Catcrafts' sources were read at fp6-img `41f6fb4` and pmaports `286d3b4`.

Conffiles: `/etc/default/fp6-lte-pin`, `/etc/apt/preferences.d/fp6-no-distro-kernels.pref`.
The guard is deliberately not one: dpkg keeps conffiles on `remove`, and a
leftover file at the diverted path would stop `postrm` from renaming the
original back. Hence the symlink.

Maintainer scripts: `preinst` adds the divert; `postrm` removes it. Everything else
comes from debhelper: `dh_installsystemd` enables both units and starts
`fp6-lte-pin` (`fp6-remoteproc-start` only runs at boot), and
`dh_installinitramfs` triggers `update-initramfs`.

The topology binary isn't in git: `tools/build-topology.sh` builds it from
Catcrafts' audioreach-topology at a pinned commit and checks its sha256; the
package build stops if it's missing.

## Tested

Installed on the phone from first boot (test1) through test8; every version
was installed and booted on hardware. Test history in short:
- test2: EROFS drop-in, touch in the initramfs;
- test3: encrypted-root cmdline;
- test4: LTE pin;
- test5: AVB relocation and the size-checking guard;
- test6–8: call audio, echo-cancel fix, apt pin, post-update hook.

`0.1` compared with test8: the same files and modes, three files differing only
in comments, the guard now reached through the symlink. Installed over test8
on the phone: the divert was kept, the initramfs trigger ran the guard, which
wrote and verified `boot_a`; a kernel-hook cycle (`run-parts` on
`/etc/kernel/postinst.d`) ran the guard through the symlink; the phone
rebooted to unl0kr, Phosh and a working modem.

## Rework before anyone else would accept it

- Split by destination: the generic parts to qcom-phone-utils, droid-juicer and
  iio-sensor-proxy; the audio parts to alsa-ucm-conf and linux-firmware; the milos
  and FP6 parts to `milos-support`; the carrier workaround to an opt-in. Some of
  it should then disappear (the apt pin, `fp6-remoteproc-start`).
- lintian: the apt pin is an error (`package-installs-apt-preferences`) by
  design; `fp6-make-bootimg` has no man page.
