# Boot, AVB and the boot partition

**Lives in:** `fp6-mobian-support`: `/etc/kernel/postinst.d/zz-qcom-bootimg`
(guard; a symlink to `/usr/lib/fp6-mobian-support/zz-qcom-bootimg`), `/usr/lib/fp6-mobian-support/{boot-is-mobian,fp6-boot-avb,fp6-reboot}`,
`/usr/sbin/fp6-make-bootimg`, `/usr/share/initramfs/post-update.d/zz-fp6-bootimg`.
**Origin:** written for this port. **Licence:** GPL-3.0-or-later.
**Upstream target:** qcom-phone-utils (the guard logic and the post-update hook);
the AVB handling in a FP6/milos install path (Mobian wiki page, installer).

## The bootloader's traps

| Trap | Consequence | How we found it |
|---|---|---|
| Writing `boot` over fastboot zeroes `modemst1`/`modemst2` | cellular and eSIM gone until NV is restored | Catcrafts isolated it while writing the fp6-img installer; we never tried |
| The stock dtbo is applied to every DTB | mainline DTB hangs on the logo | first boot hung until `dtbo_a`/`dtbo_b` were erased (Catcrafts erases them too) |
| `boot` is an **AVB-chained** partition | an oversized image destroys the vbmeta → slot refused | first install to internal storage: `Load Error`, slot marked unbootable |
| `boot` is 96 MiB, `modem.mbn` is 112.6 MB | firmware-complete initramfs can't fit | same install, see [firmware.md](firmware.md) |

### AVB details

`vbmeta_a` (flags 0) has *chain* descriptors for `boot`, `init_boot`,
`recovery` and `vbmeta_system`, and hash descriptors for `dtbo` and
`vendor_boot`. Stock `boot_a` ends with a 64-byte AVB footer. It points to a
2304-byte signed vbmeta struct at offset 35 438 592, right after the stock
Android image.

The unlocked bootloader (orange state) tolerates a hash, key or rollback
mismatch. It does **not** tolerate missing or invalid vbmeta metadata, or I/O
errors: it reports `Load Error` and marks the slot unbootable. libavb checks the
*active slot's on-disk* `boot` even for `fastboot boot`, so after that, RAM
booting fails too while the broken slot is active. `fastboot set_active <slot>`
clears the unbootable flag and retry count; it didn't touch the NV.

Catcrafts' pmOS boot image is smaller than 35 MB, which is presumably why their
plain `dd` to `boot_a` works. Ours is about 55.5 MiB: an 11.4 MiB Debian kernel
and a 44 MiB initramfs that carries firmware and unl0kr.

### Fix: move the vbmeta

`fp6-boot-avb relocate <stock boot image> <partition>` copies the unchanged
signed vbmeta to *partition size − 64 KiB*. It then rewrites only the vbmeta
offset in the footer. The bootloader accepts it (the hash no longer matches,
which unlocked tolerates). Boot images up to about 95.9 MiB now fit.

Safety checks in `relocate`:
- refuses without `FP6_ALLOW_BOOT_WRITE=1`;
- the source must have an intact footer and vbmeta, and the same size as the target;
- refuses if the boot image in the target already extends into the reserved tail;
- verifies the footer and vbmeta after writing (sha256 of the vbmeta).

`fp6-boot-avb check` reports the state. `fp6-boot-avb maxsize` prints the largest
image that leaves the AVB data intact, and fails if it isn't intact.

## The guard (`zz-qcom-bootimg` replacement)

qcom-phone-utils' `zz-qcom-bootimg` runs after kernel installs. It unpacks the
current `boot`, swaps in the new kernel and initramfs, and `dd`s the result
back. That is already NV-safe (written from Linux), but on the FP6 it would:
- overwrite stock Android while Mobian is only being RAM-boot tested;
- destroy the AVB data with an image larger than 35 MB;
- happily pack a Debian kernel that can't boot the phone, if one gets installed.

`fp6-mobian-support` diverts it (`dpkg-divert --rename`) and installs a guard
that writes only when **all** of these hold:

1. The kernel version ends in `-milos` and is the newest milos kernel
   (`-f` overrides "newest").
2. The active slot's `boot` already holds a Mobian image: its cmdline, in the
   first page for every header version, contains `mobile.root=`
   (`boot-is-mobian`). `FP6_ALLOW_BOOT_WRITE=1` overrides this one check, for
   the first deliberate install.
3. `fp6-boot-avb maxsize` succeeds (footer and vbmeta intact).
4. The new image (built by `fp6-make-bootimg`) is smaller than that maximum.

Then it writes with `conv=notrunc,fsync`, compares the read-back with the image,
and runs `fp6-boot-avb check`. In every refusal case it warns and exits 0,
because droid-juicer treats a failing hook as fatal. Outside the phone (in the
image build chroot) it hands over to the original script, which skips itself
there.

### Initramfs rebuilds outside kernel installs

Mobian repacks `boot` only from the kernel's `postinst.d` hooks. An initramfs
rebuilt by a package trigger (udev, cryptsetup, unl0kr, firmware…) never
reaches the boot partition. `zz-fp6-bootimg` in
`/usr/share/initramfs/post-update.d/` runs the guard after every
`update-initramfs`. It skips itself when called from a kernel's maintainer scripts
(`DEB_MAINT_PARAMS` set), because the kernel hook follows right after.
**This gap exists on every Mobian qcom device**, not just the FP6.

### `fp6-make-bootimg`

Builds a boot image from the installed kernel, DTB and initramfs, using the
FP6 parameters (header v2, page 4096, mkbootimg's default base 0x10000000 as on
Mobian's FP5, kernel 0x8000, ramdisk 0x1000000, DTB
0x01f00000, tags 0x100, `--os_version 99.87.36 --os_patch_level 2099-12-31` as
postmarketOS passes them). It writes no partition. It uses `mobile.root=/dev/mapper/root`
for an encrypted root (as Mobian's `bootloader.sh` does), else the filesystem
UUID. It's used by the guard, and by hand to get an image for `fastboot boot`.

### `fp6-reboot`

Replaces droid-juicer's `ExecStartPost=reboot`. If `boot` doesn't hold Mobian
(RAM-boot testing), it reboots to fastboot instead of into stock Android, which
can't boot with dtbo erased.

## Tested

- `relocate` on the real `boot_a`; the bootloader accepted the slot; cold boots since.
- Guard: refused while `boot_a` held stock; wrote and verified after droid-juicer's
  first boot (43.6 MiB initramfs); kernel reinstall cycle (44.0 MiB initramfs);
  a trigger-driven initramfs rebuild through the post-update hook.
- `fp6-reboot`: both paths (to fastboot during RAM-boot tests, plain reboot once installed).

## Rework before upstream

- The guard mixes generic logic (only write a slot that holds our image, read
  back, size and AVB checks, the post-update hook) with FP6 specifics (AVB
  relocation, milos-only kernels). The generic half belongs in
  qcom-phone-utils' own `zz-qcom-bootimg`.
- `boot-is-mobian` is a heuristic (`mobile.root=` in the cmdline).
- `FP6_LIB`, `FP6_CMDLINE` and `FP6_MAKE_BOOTIMG` are test seams for host-side
  testing. Keep them or drop them; don't document them as configuration.
- `fp6-make-bootimg` (and `wip.toml`) carry a debugging cmdline (`console=tty0
  plymouth.enable=0 loglevel=7`). It stays until a maintainer asks for it to
  go; changing it changes what the guard writes to the phone.
- Whether the bootloader needs `--os_version`/`--os_patch_level` at all is untested.
- An installer should do the first install: relocate, rootfs, boot, NV check.
  The steps are in [../reproduce.md](../reproduce.md); Catcrafts' `install.sh`
  is the precedent.
