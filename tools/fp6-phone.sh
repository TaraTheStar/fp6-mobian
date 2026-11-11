#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Checks for the phone half of docs/reproduce.md. Nothing here writes to a
# partition: the steps that do stay manual, so each one is read before the
# next. Copy it to the phone the same way as fp6-collect.sh:
#   scp tools/fp6-phone.sh mobian@10.66.0.1:
#   ssh -t mobian@10.66.0.1 sudo sh fp6-phone.sh <command> ...
#
#   backup DIR             phone, as root (section 4): dump the NV partitions
#                          and boot_a into DIR, with SHA256SUMS and the NV check
#   verify DIR [BOOT_IMG]  anywhere, e.g. the host after copying DIR over:
#                          checksums, NV check, and boot_a.img against the
#                          factory boot.img
#   nv DIR                 phone, as root (step 5.5): fsg, fsc and persist still
#                          match the backup in DIR, modemst1 isn't blank
#   boot IMAGE [PART]      phone, as root (before step 5.4): AVB data of PART
#                          (default: the active slot's boot) intact and
#                          relocated, and IMAGE small enough to fit
#   after                  internal system, as root (end of section 5): the
#                          first-boot checks
set -eu

NV="modemst1 modemst2 fsg fsc persist"
STABLE="fsg fsc persist"   # modemst1/2 may change once the modem has run
AVB=${FP6_BOOT_AVB:-/usr/lib/fp6-mobian-support/fp6-boot-avb}
RESERVE=65536              # fp6-boot-avb relocate puts the vbmeta at PART_SIZE - RESERVE

bad=0
ok()   { echo "ok    $*"; }
fail() { echo "FAIL  $*"; bad=1; }
info() { echo "      $*"; }
die()  { echo "E: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" = 0 ] || die "run as root: sudo sh $0 $*"; }
part() { p=/dev/disk/by-partlabel/$1; [ -e "$p" ] || die "no partition $1 (not on the FP6?)"; echo "$p"; }
size_of() { if [ -b "$1" ]; then blockdev --getsize64 "$1"; else stat -L -c %s "$1"; fi; }

# A blank modemst1 means the modem's NV data is gone: zeros or 0xff only
nv_check() {
    n=$(od -An -v -tx1 -N4096 "$1" | tr ' ' '\n' | grep -v '^$' | sort -u | wc -l)
    if [ "$n" -gt 2 ]; then ok "modemst1 isn't blank"; else fail "modemst1 looks blank: NV data lost?"; fi
}

cmd=${1:-}; [ $# -gt 0 ] && shift
case $cmd in
backup)
    [ $# = 1 ] || die "usage: $0 backup DIR"
    need_root backup "$@"
    D=$1; mkdir -p "$D"
    for p in $NV boot_a; do
        dd if="$(part "$p")" of="$D/$p.img" bs=1M status=none
        ok "$p → $D/$p.img ($(size_of "$D/$p.img") bytes)"
    done
    (cd "$D" && sha256sum ./*.img >SHA256SUMS)
    nv_check "$D/modemst1.img"
    if [ -n "${SUDO_USER:-}" ]; then chown -R "$SUDO_USER:" "$D"; fi
    echo
    echo "Copy $D to the host and to a second place, then run there:"
    echo "  sh tools/fp6-phone.sh verify <dir> <factory image>/boot.img"
    echo "Keep it private: these partitions are tied to this phone's identity."
    ;;
verify)
    [ $# = 1 ] || [ $# = 2 ] || die "usage: $0 verify DIR [FACTORY_BOOT_IMG]"
    D=$1
    if (cd "$D" && sha256sum -c --quiet SHA256SUMS); then ok "checksums match SHA256SUMS"; else fail "checksums"; fi
    for p in $NV boot_a; do [ -s "$D/$p.img" ] || fail "$p.img missing or empty"; done
    nv_check "$D/modemst1.img"
    if [ $# = 2 ]; then
        [ -f "$2" ] || die "$2 not found: give the boot.img from the factory image"
        if cmp -s "$D/boot_a.img" "$2"; then ok "boot_a.img is identical to $2"
        else fail "boot_a.img differs from $2: the wrong factory image, or boot_a isn't stock any more"; fi
    else
        info "no factory boot.img given: boot_a.img not compared"
    fi
    ;;
nv)
    [ $# = 1 ] || die "usage: $0 nv DIR"
    need_root nv "$@"
    D=$1
    for p in $STABLE; do
        [ -f "$D/$p.img" ] || die "$D/$p.img missing: the backup from section 4"
        if cmp -s "$(part "$p")" "$D/$p.img"; then ok "$p matches the backup"; else fail "$p differs from the backup"; fi
    done
    nv_check "$(part modemst1)"
    ;;
boot)
    [ $# = 1 ] || [ $# = 2 ] || die "usage: $0 boot IMAGE [PART]"
    IMG=$1
    if [ $# = 2 ]; then P=$2; else
        need_root boot "$@"
        s=$(qbootctl -x 2>/dev/null) || die "can't read the active slot (qbootctl -x)"
        P=$(part "boot$s")
    fi
    [ "$(head -c 8 "$IMG")" = "ANDROID!" ] || die "$IMG isn't an Android boot image"
    info "image cmdline: $(dd if="$IMG" bs=1 skip=64 count=512 status=none | tr -d '\000')"
    if out=$("$AVB" check "$P" 2>&1); then ok "$out"; else fail "$out"; fi
    [ "$bad" = 0 ] || { echo "Don't write $P: its AVB data isn't intact (see docs/reproduce.md, Load Error)."; exit 1; }
    max=$("$AVB" maxsize "$P")
    if [ "$max" = $(( $(size_of "$P") - RESERVE )) ]; then
        ok "vbmeta relocated to the end of $P"
    else
        fail "vbmeta still at offset $max, where stock puts it: relocate it first (step 5.3)"
    fi
    sz=$(size_of "$IMG")
    if [ "$sz" -lt "$max" ]; then ok "image ($sz bytes) fits below $max"; else fail "image ($sz bytes) doesn't fit below $max"; fi
    ;;
after)
    need_root after
    if [ -s /var/lib/droid-juicer/status.json ]; then
        ok "droid-juicer ran: $(grep -c '"/' /var/lib/droid-juicer/status.json) paths in its status.json"
    else
        fail "/var/lib/droid-juicer/status.json missing: droid-juicer hasn't finished"
    fi
    fw=/lib/firmware/updates/qcom/milos/fairphone/fp6/modem_pr
    n=$(find "$fw" -type f 2>/dev/null | wc -l)
    if [ "$n" = 172 ]; then ok "$fw holds 172 files"; else fail "$fw holds $n files, expected 172"; fi
    r=0; for s in /sys/class/remoteproc/*/state; do
        if [ "$(cat "$s")" = running ]; then r=$((r + 1)); fi
    done
    if [ "$r" = 4 ]; then ok "4 remoteprocs running"; else fail "$r of 4 remoteprocs running"; fi
    if out=$("$AVB" check 2>&1); then ok "$out"; else fail "$out"; fi
    info "slot state, should show the active slot marked successful:"
    qbootctl 2>&1 | sed 's/^/      /'
    ;;
*)
    sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac
[ "$bad" = 0 ] || { echo; echo "some checks failed: stop and look before the next step"; exit 1; }
