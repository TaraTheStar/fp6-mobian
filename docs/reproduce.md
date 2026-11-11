# Reproduce it: build and install

This installs Mobian to the phone's internal storage and replaces the stock
OS. Read the whole page first. The order of the steps is what keeps the modem
working.

**At your own risk.** This is unofficial: neither Fairphone nor Mobian
supports it. A mistake can leave the phone without cellular service, unable
to boot, or wiped, and lost NV data can't be restored without the backup from
section 4. Check what your warranty covers before you unlock. The code and
these instructions come with no warranty of any kind (sections 15 and 16 of
the [licence](https://github.com/TaraTheStar/fp6-mobian/blob/main/LICENSE)).

## The rules

1. **Never `fastboot flash boot`** (or `fastboot flash` anything else). On the
   FP6, the bootloader zeroes `modemst1`/`modemst2`, the modem's NV data, whenever
   `boot` is written over fastboot. Catcrafts isolated this. Without NV the
   phone has no cellular service and no eSIM. Write every partition **from a
   running Linux with `dd`**.
2. **The only fastboot writes allowed are `fastboot erase dtbo_a` and `fastboot erase dtbo_b`.**
   `fastboot boot <image>` (RAM boot) writes nothing and is safe.
3. **Back up the NV partitions before anything else**: `modemst1`, `modemst2`,
   `fsg`, `fsc`, `persist`. They're unique to your phone. Keep a copy off the
   laptop too, and **never publish them**: they're tied to your device's identity.
4. **`boot` is an AVB-chained partition.** Its last 64 bytes point to a signed
   vbmeta inside the partition, just after the 35 MB stock image. A bigger image
   written over it destroys that vbmeta. The bootloader then refuses the slot
   (`Load Error`), even unlocked, and even `fastboot boot` fails while that slot
   is active. Move the vbmeta first (step 5.3), and write boot images only
   through the guard or after checking `fp6-boot-avb maxsize`.
5. **Erase dtbo.** The bootloader applies the stock device-tree overlay to any
   DTB it boots, and a mainline DTB then hangs on the logo. With dtbo erased,
   stock /e/OS doesn't boot until you restore it.
6. **Never wipe `super`, `modem` or `bluetooth`.** They hold the vendor
   firmware, and droid-juicer extracts it from them on the first boot of every
   install.
7. Don't relock the bootloader with a custom image.
8. A plain reboot boots the *active slot*. During testing, while that slot still
   holds stock Android, reboot with `systemctl reboot --reboot-argument=bootloader`
   to land in fastboot.

Details and the reasoning behind each rule: [components/boot-and-avb.md](components/boot-and-avb.md).

## What you need

- A Fairphone (Gen. 6) whose bootloader can be unlocked (section 2).
- The **factory image for the exact stock version on the phone**. It provides
  the stock `dtbo.img` for rollback; keep it and check its checksum.
- A microSD card of 16 GB or more, for a test system that boots without
  touching internal storage. It stays useful afterwards as a rescue system.
  The unpacked rootfs is 7.45 GiB, and many cards sold as 8 GB are smaller
  than that.
- An x86-64 Linux host with podman, KVM, and qemu-user binfmt (for the arm64
  imsd build); `fastboot`, `adb` and `simg2img` (Debian:
  `fastboot adb android-sdk-libsparse-utils`). For access to the phone over USB
  without root, install `android-sdk-platform-tools-common` (udev rules), add
  your user to `plugdev`, reload udev and replug the phone.
- If you depend on VoLTE: test it on the stock OS first, so you know your
  carrier provisions the SIM for it.

## 1. Build

All builds run in containers defined in `tools/` (Debian forky).

**In one go:** `tools/fp6-build.sh -k ~/.ssh/id_ed25519.pub` checks the host,
then runs 1.1 to 1.4 in order, in `fp6-work/` next to the repository (`-w` to
change it). The `-k` key is the one the image will accept for SSH. It builds an
encrypted Phosh image unless told otherwise (`-p` for a plain root,
`-e plasma-mobile`), and a rerun after a failure resumes where it stopped. The
boot image, the raw rootfs and the packages end up in `fp6-work/out/`. The
steps below are what it runs.

### 1.1 Kernel

The kernel source package is Mobian's `qcom-linux` packaging, set to 7.3, with
the patch series and config fragment from `kernel/`
([components/kernel.md](components/kernel.md)). `kernel/regen.sh` assembles it
from upstream (kernel.org, milos-mainline, Catcrafts, `qcom-linux`) and checks
every patch against the recorded series:

```sh
kernel/regen.sh ../kernel-build          # about 2 minutes plus downloads
podman build -t fp6-debbuild:forky -f tools/Containerfile.debbuild tools
cd ../kernel-build
podman run --rm --userns=keep-id --user "$(id -u):$(id -g)" \
    -v "$PWD":/build -w /build/linux-7.3-milos-7.3 fp6-debbuild:forky \
    dpkg-buildpackage -a arm64 -Pcross -d -us -uc -b
```

`-d` skips the build-dependency check; the container provides the
dependencies.

You only need `linux-image-7.3-milos_*.deb`. `linux-headers` is for building
out-of-tree modules on the phone, which is untested.

### 1.2 imsd

```sh
podman build --arch arm64 -t fp6-imsd:forky-arm64 -f tools/Containerfile.imsd tools
# in a work directory: the orig tarball from upstream tag v1.1.0 (commit 547361a)
git clone --branch v1.1.0 https://forgejo.catcrafts.net/Catcrafts/imsd.git imsd-git
git -C imsd-git archive --prefix=imsd-1.1.0/ v1.1.0 | xz > imsd_1.1.0.orig.tar.xz
tar xf imsd_1.1.0.orig.tar.xz
cp -r <this repo>/packaging/imsd/debian imsd-1.1.0/
podman run --rm --arch arm64 --userns=keep-id --user "$(id -u):$(id -g)" \
    -v "$PWD":/w:Z -w /w/imsd-1.1.0 fp6-imsd:forky-arm64 \
    dpkg-buildpackage -us -uc -b
```

About 10 minutes under qemu. You need `imsd` and `imsd-ofono` (Phosh/GNOME
Calls), or `imsd-plasma` for Plasma Mobile (untested).

### 1.3 fp6-mobian-support

`Architecture: all`. The AudioReach topology is built from source first; the
script checks it against a pinned hash:

```sh
tools/build-topology.sh
podman build -t fp6-imsd:forky -f tools/Containerfile.imsd tools   # has debhelper
podman run --rm --userns=keep-id --user "$(id -u):$(id -g)" \
    -v "$PWD/packaging":/w:Z -w /w/fp6-mobian-support fp6-imsd:forky \
    dpkg-buildpackage -us -uc -b
```

### 1.4 Image

Clone [mobian-recipes] at commit `a4fff86` and apply the patches, including the
droid-juicer config (as a file in the recipes' overlay):

```sh
git am <this repo>/patches/mobian-recipes/*.patch
git apply -p2 --directory=devices/qcom/droid-juicer <this repo>/patches/droid-juicer/*.patch
```

Put the `.deb` files from above into `devices/qcom/packages/`, add your SSH
public key as `overlays/ssh/authorized_keys`, then:

```sh
podman build -t fp6-debos -f tools/Containerfile.debos tools
podman run --rm --device /dev/kvm --security-opt label=disable \
    -v "$PWD":/recipes -w /recipes --entrypoint sh fp6-debos \
    -c './build-fp6.sh -c'
```

`-c` builds an encrypted root. The defaults are user `mobian`, password `1234`,
and the LUKS passphrase is the same unless you pass `-R`. Keep the defaults in
the build and change them on the phone (section 7); don't put real secrets into
build arguments or shell history. The build takes about 70 minutes.

Output: `mobian-wip-phosh-<date>.boot-fp6.img` (boot image) and
`mobian-wip-phosh-<date>.rootfs.img` (Android sparse). For internal storage
you need the raw image: `simg2img rootfs.img rootfs.raw`. It's 7.5 GB, so
don't put it in `/tmp` if that's a tmpfs on your host.

Check before going near the phone: `tools/bootimg-info.py` on the boot image
(header v2, page size 4096, `mobile.root=` in the cmdline, DTB present), and
`cryptsetup luksDump` on the raw rootfs.

## 2. Unlock the bootloader

Unlocking wipes the phone's user data.

1. On the stock OS, install any pending system updates first.
2. Enable the developer options (tap the build number in *About phone*), then
   turn on **USB debugging** and **OEM unlocking**. If the OEM unlocking toggle
   is greyed out, the phone needs more time online before it allows it.
3. If the phone asks for an unlock code, request one from Fairphone with IMEI 1
   and the serial number. Only the newest code works: each request voids the
   earlier ones. No code was needed from Fairphone OS FP6.QREL.16.69.0 on, nor
   on /e/OS 4.4.2.
4. Reboot to fastboot (`adb reboot bootloader`, or power off and hold
   Vol-down + Power) and unlock:
   ```sh
   fastboot flashing get_unlock_ability   # must print 1
   fastboot flashing unlock               # confirm on the phone: Vol-up, then Power
   fastboot getvar unlocked               # must print yes
   ```

`fastboot flashing unlock_critical` only opens the bootloader's own
partitions. Nothing here needs it.

## 3. First boot from microSD (writes nothing internal except dtbo)

1. In fastboot:
   ```sh
   fastboot erase dtbo_a
   fastboot erase dtbo_b
   ```
2. On the host, write the rootfs to the microSD card: a GPT with one partition
   spanning the card, `dd` the raw image into that partition, and check with
   `blkid` that the partition now shows as `crypto_LUKS`. Then grow the
   filesystem inside: `cryptsetup open` → `e2fsck -f` → `resize2fs` →
   `cryptsetup close`.
3. Put the card in the phone. It shares the SIM tray.
4. `fastboot boot mobian-wip-phosh-<date>.boot-fp6.img`. Right after power-on,
   the first `fastboot boot` sometimes fails with "Command failed"; retry. If it
   keeps failing with `Load Error`, run `fastboot reboot bootloader`, then try again.
5. Unlock at the unl0kr prompt. On first boot, droid-juicer copies the firmware
   from the stock partitions (read-only) and rebuilds the initramfs. Because
   `boot` still holds stock Android, the guard refuses to write it, and the
   phone reboots **to fastboot**.
6. RAM-boot the same image again. Then, over SSH (`ssh mobian@10.66.0.1`), build
   a boot image that includes the firmware, and copy it to the host:
   ```sh
   sudo fp6-make-bootimg            # writes /var/lib/fp6-mobian-support/boot.img, no partition
   ```
   From now on, RAM-boot that image. Check the hardware (`tools/fp6-collect.sh`
   collects logs, read-only).

## 4. Back up (from the microSD system, read-only)

```sh
for p in modemst1 modemst2 fsg fsc persist boot_a; do
    sudo dd if=/dev/disk/by-partlabel/$p of=$p.img status=none
done
sha256sum *.img > SHA256SUMS
```

Copy the images to the host and to a second place. `boot_a.img` should match
`boot.img` from the factory image. Keep both: step 5.3 needs the stock vbmeta from it.

Health check for the modem NV: `modemst1` must not be blank:
`od -An -tx1 -N4096 modemst1.img | sort -u | wc -l` must print more than 2.
`fsg`, `fsc` and `persist` should never change under Linux. `modemst1`/`2` may
change legitimately once the modem has run.

`tools/fp6-phone.sh` does this section and the checks in the next one. It
never writes a partition. Copy it to the phone, take the backup there, then
check the copy on the host:

```sh
scp tools/fp6-phone.sh mobian@10.66.0.1:
ssh -t mobian@10.66.0.1 sudo sh fp6-phone.sh backup fp6-backup
scp -r mobian@10.66.0.1:fp6-backup .
tools/fp6-phone.sh verify fp6-backup <factory image>/boot.img
```

## 5. Install to internal storage (from the microSD system)

Every step here writes to the phone. Run them one at a time and read the output.

Feeding `sudo` a password with `-S` eats the first bytes of a piped stream. For the
streaming steps, use `sudo -A` with an askpass helper in `/run/user/<uid>`
(tmpfs). Delete it afterwards.

1. **Slot.** `qbootctl` shows the active slot. These steps assume `a`. While the
   microSD system runs and `boot_a` holds a Mobian image, its own guard would
   write `boot_a` after any kernel or initramfs change. Don't install packages
   on the microSD system during the install.
2. **Rootfs.** Optionally discard the old (encrypted, now unusable) user data
   first (`blkdiscard -f /dev/disk/by-partlabel/userdata`). Then stream the raw
   image from the host:
   ```sh
   ssh mobian@10.66.0.1 'sudo -A dd of=/dev/disk/by-partlabel/userdata bs=4M conv=fsync' < rootfs.raw
   ```
   Read it back (`sudo head -c <size> /dev/disk/by-partlabel/userdata | sha256sum`).
   The LUKS data segment spans the whole device, so only the filesystem
   inside needs growing: `cryptsetup open` → `e2fsck -f` → `resize2fs` → `cryptsetup close`.
3. **Move the AVB vbmeta** to the end of `boot_a`, from the stock image you
   backed up:
   ```sh
   sudo FP6_ALLOW_BOOT_WRITE=1 /usr/lib/fp6-mobian-support/fp6-boot-avb relocate boot_a-stock.img /dev/disk/by-partlabel/boot_a
   sudo /usr/lib/fp6-mobian-support/fp6-boot-avb check /dev/disk/by-partlabel/boot_a
   ```
   This copies the unchanged, still validly signed vbmeta to *partition size − 64 KiB*
   and points the footer at it. Boot images up to about 95.9 MiB then fit.
4. **Boot image.** Check that the image is smaller than
   `fp6-boot-avb maxsize /dev/disk/by-partlabel/boot_a`, then write it **without
   truncating** and read it back:
   ```sh
   ssh mobian@10.66.0.1 'sudo -A dd of=/dev/disk/by-partlabel/boot_a bs=1M conv=notrunc,fsync' < boot-fp6.img
   ```
   Then run `fp6-boot-avb check` again. With the image copied to the phone,
   `sudo sh fp6-phone.sh boot boot-fp6.img` runs the checks before the write:
   AVB data intact, vbmeta relocated, image small enough. Use the image from the build, not the
   microSD system's image: its cmdline must name the internal root
   (`mobile.root=/dev/mapper/root`, unlocked via the crypttab in its initramfs).
5. **NV again.** Compare `fsg`, `fsc` and `persist` with the backup, and check that `modemst1`
   is not blank: `sudo sh fp6-phone.sh nv fp6-backup`.
6. Power off, take the microSD card out, power on.

First boot from internal: bootloader (orange-state warning) → unl0kr → droid-juicer
extracts the firmware → initramfs rebuilt → the guard writes `boot_a`
(Mobian image present, AVB intact, image fits, read-back verified) → reboot →
unl0kr → Phosh.

Checks:
- `/var/lib/droid-juicer/status.json`
- `/lib/firmware/updates/qcom/milos/fairphone/fp6/modem_pr/` holds 172 files
- `cat /sys/class/remoteproc/*/state` shows 4× `running`
- `qbootctl` shows the slot marked successful

`sudo sh fp6-phone.sh after` runs them all. `qbootctl` first prints
`Couldn't find cmdline arg: 'slot_suffix'` and `Unable to read boot slot
property`. That's harmless: the kernel command line has no Android slot
suffix, so it reads the slot from the partition table instead.

If the bootloader refuses the slot (`Load Error`), `fastboot set_active a` is
not enough: it clears the "unbootable" flag, but the bootloader still checks
slot a's `boot` on disk, so even `fastboot boot` keeps failing. Make the other
slot active instead (`fastboot set_active b`; its `boot` is still stock and
intact), RAM-boot the microSD system, and repair `boot_a` from there. With
slot b active, the microSD system's own guard leaves `boot_a` alone. Then
`fastboot set_active a`.

## 6. Kernel updates

`apt` installs a new `linux-image-*-milos` → `update-initramfs` → the guard
rebuilds the boot image and writes it to the active slot, with the same checks.
Initramfs rebuilds triggered by other packages go the same way. Test one update
cycle (`apt-get reinstall ./linux-image-7.3-milos_*.deb`) before you rely on the phone.

An apt pin in fp6-mobian-support keeps Debian's and Mobian's own kernels off
the phone, because they can't boot it.

## 7. Make it yours

- Change the LUKS passphrase and the user password **on the phone**:
  `sudo cryptsetup luksChangeKey /dev/disk/by-partlabel/userdata`, `passwd`.
- Changing the passphrase doesn't change the volume key that encrypts the
  data, and that key is the one in the image you built. Anyone with the image
  and its default passphrase can still decrypt the phone's `userdata`. Once
  the phone works, delete the image (`rootfs.img`, `rootfs.raw`) and any copy
  of it. Re-encrypting with a new volume key (`cryptsetup reencrypt`) removes
  the dependency entirely, but hasn't been tested on the FP6's root filesystem
  yet.
- APN: create the mobile data connection in Settings or with `nmcli`
  (T-Mobile US: `fast.t-mobile.com`).
- VoLTE: imsd and imsd-ofono are preinstalled and start with ModemManager.
  GNOME Calls uses the `ofono` provider (set by imsd-ofono). See
  [components/modem-and-volte.md](components/modem-and-volte.md) for the
  settings, including `fp6-lte-pin` (on by default, LTE only), which you may not
  want on your carrier.
- Flathub: if the system `flathub` remote points at `https://flathub.org`, re-add it
  from `https://dl.flathub.org/repo/flathub.flatpakrepo`.

### A separate encrypted `/home`

A second LUKS volume (e.g. `/home` on microSD) chain-unlocks with a keyfile on
the encrypted root.

1. Create the keyfile on the root, `root:root` with mode `0400`, and add it to
   the volume with `cryptsetup luksAddKey`.
2. Add `home_crypt UUID=<luks-uuid> /root/keyfile luks,nofail` to
   `/etc/crypttab`, plus the matching `/etc/fstab` line with `nofail`.
3. Keep SSH working when `/home` doesn't unlock: put the authorized keys in
   `/etc/ssh/authorized_keys/<user>` (owned by root) and add a drop-in in
   `/etc/ssh/sshd_config.d/` with
   `AuthorizedKeysFile .ssh/authorized_keys /etc/ssh/authorized_keys/%u`.
4. Check the chain without rebooting, then reboot once:
   ```sh
   sudo systemctl daemon-reload
   sudo systemctl start systemd-cryptsetup@home_crypt
   sudo mount /home
   ls -ln /home          # the owner UID must match `id -u <user>`
   ```
5. A `/home` from another phone brings that phone's settings. If it sets GNOME
   Calls' `autoload-plugins` (e.g. `['mm', 'sip']`), that overrides
   imsd-ofono's `['ofono']`, and calls bypass imsd. Reset it as the user, and
   the screen blank delay with it:
   ```sh
   gsettings reset org.gnome.Calls autoload-plugins
   gsettings reset org.gnome.desktop.session idle-delay
   ```

## Troubleshooting

| Symptom | Cause, and what to do |
|---|---|
| The phone powers off at the passphrase prompt, or comes up in fastboot by itself | unl0kr powers off after 5 minutes without input (`timeout=300`). With USB connected, the phone then starts in fastboot, which looks as if it went to the bootloader. Boot again and enter the passphrase |
| Black screen and no USB device on the host after about 2 minutes | Hold Power for 15–20 s to force it off, then boot again |
| The panel stays dark, but the host has an `enx…` network device | The system is up: SSH in (`ssh mobian@10.66.0.1`) |
| The `enx…` device is there, but 10.66.0.1 doesn't answer | The host has no address on it: `sudo ip addr add 10.66.0.2/24 dev enx…` |
| The bootloader refuses the slot (`Load Error`) | See the end of section 5: switch to the other slot and repair from the microSD system |

### Repairing the internal system from the microSD card

To install a fixed package on the internal system without booting it, boot the
microSD system and work in a chroot. Turn off initramfs updates in the target
first: otherwise the package's scripts rebuild the initramfs, and with it the
boot image, from inside the chroot.

```sh
sudo cryptsetup open /dev/disk/by-partlabel/userdata internal
sudo mount /dev/mapper/internal /mnt
for d in dev proc sys run; do sudo mount --bind /$d /mnt/$d; done
sudo sed -i 's/^update_initramfs=.*/update_initramfs=no/' /mnt/etc/initramfs-tools/update-initramfs.conf
sudo cp fixed.deb /mnt/tmp/ && sudo chroot /mnt dpkg -i /tmp/fixed.deb
sudo sed -i 's/^update_initramfs=no/update_initramfs=yes/' /mnt/etc/initramfs-tools/update-initramfs.conf
for d in run sys proc dev; do sudo umount /mnt/$d; done
sudo umount /mnt && sudo cryptsetup close internal
```

## Rollback

- **To the microSD system:** insert the card and `fastboot boot` its boot image.
  Both systems coexist only if their LUKS and filesystem UUIDs differ, so the
  card needs its own image build: writing the same `rootfs.img` to the card and
  to `userdata` gives both the same UUIDs. While the microSD system runs with
  slot a active, its guard writes `boot_a` on any kernel or initramfs change:
  don't install packages there.
- **To stock /e/OS:** from a Linux boot, `dd` the stock `dtbo.img` to `dtbo_a`
  and `dtbo_b` and your `boot_a` backup to `boot_a`. Then reboot and factory-reset
  (the user data is gone). If a fastboot write to `boot` ever happens anyway,
  RAM-boot Linux and `dd` the NV backup back to `modemst1`, `modemst2`, `fsg`,
  `fsc` and `persist`.

[mobian-recipes]: https://salsa.debian.org/Mobian-team/mobian-recipes
