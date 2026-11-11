#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Build everything for a Fairphone (Gen. 6) install on the host: the kernel,
# imsd, fp6-mobian-support and the Mobian image. Section 1 of
# docs/reproduce.md, as one command. Nothing here touches a phone.
#
# Usage: tools/fp6-build.sh -k KEY.pub [-w DIR] [-e ENV] [-p] [-f]
#   -k KEY.pub  SSH public key the image accepts for `mobian` (required)
#   -w DIR      work directory (default: fp6-work next to this repository)
#   -e ENV      phosh (default) or plasma-mobile
#   -p          plain root filesystem instead of an encrypted one
#   -f          rebuild stages that already finished
#
# Stages run in order: check, kernel, imsd, support, image. A finished stage
# leaves DIR/.done-<stage>, so a rerun after a failure picks up where it
# stopped. Logs go to DIR/logs/. The results end up in DIR/out/.
set -eu

IMSD_REPO=https://forgejo.catcrafts.net/Catcrafts/imsd.git
IMSD_TAG=v1.1.0
IMSD_COMMIT=547361a4d476014adccf66170adea19d762bc9e8
RECIPES_REPO=https://salsa.debian.org/Mobian-team/mobian-recipes.git
RECIPES_COMMIT=a4fff86693de2526e4de1d0497b74b2400986e6f
KSRC=linux-7.3-milos-7.3

TOOLS=$(dirname "$(realpath "$0")")
REPO=$(dirname "$TOOLS")

usage() { sed -n '7,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
KEY="" W="$(dirname "$REPO")/fp6-work" ENV=phosh CRYPT=-c FORCE=0
while getopts k:w:e:pfh o; do
    case $o in
        k) KEY=$OPTARG ;;
        w) W=$OPTARG ;;
        e) ENV=$OPTARG ;;
        p) CRYPT="" ;;
        f) FORCE=1 ;;
        *) usage ;;
    esac
done
[ -n "$KEY" ] || { echo "-k KEY.pub is required: the image only accepts SSH logins with that key" >&2; usage; }
[ -f "$KEY" ] || { echo "no such file: $KEY" >&2; exit 1; }
case "$(head -c 4 "$KEY")" in
    ssh-|ecds|sk-*) ;;
    *) echo "$KEY doesn't look like an OpenSSH public key" >&2; exit 1 ;;
esac
case $ENV in phosh|plasma-mobile) ;; *) echo "-e: phosh or plasma-mobile" >&2; exit 2 ;; esac
KEY=$(realpath "$KEY")
mkdir -p "$W/logs" "$W/out"
W=$(realpath "$W")

say() { printf '\n== %s\n' "$*"; }
# run LOG CMD...: output to the stage log; on failure show its tail and stop
run() {
    log=$W/logs/$1.log; shift
    echo "\$ $*" >>"$log"
    "$@" >>"$log" 2>&1 || {
        echo "failed: $*" >&2; echo "--- last lines of $log:" >&2
        tail -n 30 "$log" >&2; exit 1
    }
}
done_already() {
    [ "$FORCE" = 0 ] && [ -f "$W/.done-$1" ] && [ "$(cat "$W/.done-$1")" = "${2:-}" ] && {
        echo "already built (rerun with -f to rebuild)"; return 0; }
    return 1
}
finish() { echo "${2:-}" >"$W/.done-$1"; }

# ---------------------------------------------------------------- check
say "check: host"
missing="" fail=0
need() { command -v "$1" >/dev/null 2>&1 || missing="$missing $2"; }
need podman podman;  need git git;  need curl curl;  need xz xz-utils
need simg2img android-sdk-libsparse-utils;  need fastboot fastboot;  need adb adb
need python3 python3
[ -n "$missing" ] && { echo "missing; on Debian: sudo apt install$missing"; fail=1; }
[ "$(uname -m)" = x86_64 ] || { echo "the containers and fakemachine expect an x86-64 host"; fail=1; }
[ -r /dev/kvm ] && [ -w /dev/kvm ] || { echo "/dev/kvm isn't usable: enable KVM and add yourself to the kvm group"; fail=1; }
grep -qs '^enabled' /proc/sys/fs/binfmt_misc/qemu-aarch64 ||
    { echo "no qemu-aarch64 binfmt handler (imsd is built under emulation); on Debian: sudo apt install qemu-user-binfmt"; fail=1; }
[ "$fail" = 0 ] || exit 1
# Needed later for the phone, not for building
rules=""
for d in /usr/lib/udev/rules.d /lib/udev/rules.d /etc/udev/rules.d; do
    if [ -f "$d/51-android.rules" ]; then rules=$d/51-android.rules; fi
done
[ -n "$rules" ] || echo "note: no udev rules for fastboot/adb; on Debian: sudo apt install android-sdk-platform-tools-common"
id -nG | tr ' ' '\n' | grep -qx plugdev || echo "note: you're not in plugdev, so fastboot/adb need root: sudo adduser $(id -un) plugdev, then log in again"
echo "work directory: $W ($(df -h --output=avail "$W" | tail -n 1 | tr -d ' ') free)"

# ---------------------------------------------------------------- kernel
say "kernel: linux-image-7.3-milos (about 2 minutes plus downloads, then the build)"
if ! done_already kernel; then
    mkdir -p "$W/kernel"
    rm -rf "${W:?}/kernel/$KSRC"
    run kernel "$REPO/kernel/regen.sh" "$W/kernel"
    run kernel podman build -t fp6-debbuild:forky -f "$TOOLS/Containerfile.debbuild" "$TOOLS"
    run kernel podman run --rm --userns=keep-id --user "$(id -u):$(id -g)" \
        -v "$W/kernel":/build -w "/build/$KSRC" fp6-debbuild:forky \
        dpkg-buildpackage -a arm64 -Pcross -d -us -uc -b
    finish kernel
fi
ls "$W"/kernel/linux-image-7.3-milos_*_arm64.deb

# ---------------------------------------------------------------- imsd
say "imsd: $IMSD_TAG (about 10 minutes under qemu)"
if ! done_already imsd; then
    mkdir -p "$W/imsd"; cd "$W/imsd"
    [ -d imsd-git ] || run imsd git clone -q "$IMSD_REPO" imsd-git
    got=$(git -C imsd-git rev-parse "$IMSD_TAG^{commit}")
    [ "$got" = "$IMSD_COMMIT" ] || { echo "imsd $IMSD_TAG is $got, expected $IMSD_COMMIT" >&2; exit 1; }
    git -C imsd-git archive --prefix=imsd-1.1.0/ "$IMSD_TAG" | xz >imsd_1.1.0.orig.tar.xz
    rm -rf imsd-1.1.0 && tar xf imsd_1.1.0.orig.tar.xz
    cp -r "$REPO/packaging/imsd/debian" imsd-1.1.0/
    run imsd podman build --arch arm64 -t fp6-imsd:forky-arm64 -f "$TOOLS/Containerfile.imsd" "$TOOLS"
    run imsd podman run --rm --arch arm64 --userns=keep-id --user "$(id -u):$(id -g)" \
        -v "$W/imsd":/w:Z -w /w/imsd-1.1.0 fp6-imsd:forky-arm64 dpkg-buildpackage -us -uc -b
    finish imsd
fi
ls "$W"/imsd/imsd_*_arm64.deb

# ---------------------------------------------------------------- support
say "support: fp6-mobian-support"
if ! done_already support; then
    # Built from a copy, so the repository stays clean
    rm -rf "$W/support" && mkdir -p "$W/support"
    cp -r "$REPO/packaging/fp6-mobian-support" "$W/support/"
    run support "$TOOLS/build-topology.sh" \
        "$W/support/fp6-mobian-support/audio/MILOS-Fairphone-Gen6-tplg.bin"
    run support podman build -t fp6-imsd:forky -f "$TOOLS/Containerfile.imsd" "$TOOLS"
    run support podman run --rm --userns=keep-id --user "$(id -u):$(id -g)" \
        -v "$W/support":/w:Z -w /w/fp6-mobian-support fp6-imsd:forky dpkg-buildpackage -us -uc -b
    finish support
fi
ls "$W"/support/fp6-mobian-support_*_all.deb

# ---------------------------------------------------------------- image
opts="env=$ENV crypt=${CRYPT:-no} key=$(sha256sum <"$KEY" | cut -c1-16)"
say "image: Mobian $ENV, ${CRYPT:+encrypted }root (about 70 minutes)"
if ! done_already image "$opts"; then
    R=$W/mobian-recipes
    rm -rf "$R"
    run image git clone -q "$RECIPES_REPO" "$R"
    run image git -C "$R" -c advice.detachedHead=false checkout -q "$RECIPES_COMMIT"
    # git am needs a committer; these commits never leave the work directory
    run image git -C "$R" -c user.name=fp6-build -c user.email=fp6-build@localhost.invalid \
        am -q "$REPO"/patches/mobian-recipes/*.patch
    run image git -C "$R" apply -p2 --directory=devices/qcom/droid-juicer "$REPO"/patches/droid-juicer/*.patch
    mkdir -p "$R/devices/qcom/packages" "$R/overlays/ssh"
    cp "$W"/kernel/linux-image-7.3-milos_*_arm64.deb "$W"/support/fp6-mobian-support_*_all.deb \
       "$W"/imsd/imsd_*_arm64.deb "$R/devices/qcom/packages/"
    case $ENV in
        phosh) cp "$W"/imsd/imsd-ofono_*_arm64.deb "$R/devices/qcom/packages/" ;;
        plasma-mobile) cp "$W"/imsd/imsd-plasma_*_arm64.deb "$R/devices/qcom/packages/" ;;
    esac
    cp "$KEY" "$R/overlays/ssh/authorized_keys"
    run image podman build -t fp6-debos -f "$TOOLS/Containerfile.debos" "$TOOLS"
    envarg=""; [ "$ENV" = phosh ] || envarg="-e $ENV"
    run image podman run --rm --device /dev/kvm --security-opt label=disable \
        -v "$R":/recipes -w /recipes --entrypoint sh fp6-debos -c "./build-fp6.sh $CRYPT $envarg"
    rm -f "$W"/out/*
    mv "$R"/mobian-wip-*.boot-fp6.img "$R"/mobian-wip-*.rootfs.img "$W/out/"
    finish image "$opts"
fi

# ---------------------------------------------------------------- results
say "results in $W/out"
cd "$W/out"
boot=$(ls ./*.boot-fp6.img); rootfs=$(ls ./*.rootfs.img)
raw=${rootfs%.img}.raw
[ -f "$raw" ] || simg2img "$rootfs" "$raw"
python3 -I "$TOOLS/bootimg-info.py" "$boot"
# LUKS: "LUKS\272\276" at 0; ext4: 0xEF53 (little-endian) at 1080
if [ "$(od -An -c -N 6 "$raw" | tr -d ' ')" = 'LUKS272276' ]; then type=crypto_LUKS
elif [ "$(od -An -tx1 -j 1080 -N 2 "$raw" | tr -d ' ')" = 53ef ]; then type=ext4
else type=""; fi
echo "rootfs: $raw is ${type:-unrecognised}"
want=ext4; [ -n "$CRYPT" ] && want=crypto_LUKS
[ "$type" = "$want" ] || { echo "expected $want" >&2; exit 1; }
cp "$W"/kernel/linux-image-7.3-milos_*_arm64.deb "$W"/support/fp6-mobian-support_*_all.deb \
   "$W"/imsd/imsd_*_arm64.deb "$W"/imsd/imsd-ofono_*_arm64.deb "$W"/imsd/imsd-plasma_*_arm64.deb .
cat <<EOF

Done. Next: docs/reproduce.md section 2 (unlock), then section 3 with
  $W/out/$(basename "$boot")
  $W/out/$(basename "$raw")
The image's defaults are user mobian, password 1234${CRYPT:+, LUKS passphrase 1234}:
change them on the phone (section 7).
EOF
