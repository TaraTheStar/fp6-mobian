#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Rebuild the linux-7.3-milos source package from its upstream sources:
#   - Linux 7.3 from kernel.org (sha256 pinned);
#   - milos-mainline and Catcrafts commits, fetched one by one as patches
#     (upstream.txt, in series order) and applied with `git am` on top of it;
#     three Catcrafts patches first get a fix-up (fixups/), which moves their
#     DTS hunks to where they land in the linear series;
#   - debian/ from Mobian's qcom-linux branch wip/tiol/7.2-milos (pinned
#     commit), plus packaging/*.patch, milos.config, README.milos-linux and
#     series from this directory.
# Every regenerated patch is checked against patches.sha256 (content without
# the first line, which carries a commit id that differs from tree to tree).
#
# Usage: kernel/regen.sh <work_dir>
# Leaves in <work_dir>: linux-7.3-milos_7.3.orig.tar.xz and linux-7.3-milos-7.3/
# (source + debian/), ready for dpkg-buildpackage. Downloads stay in
# <work_dir>/dl and are reused by later runs.
set -eu

KVER=7.3
SRCPKG=linux-$KVER-milos
TARBALL_URL=https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-$KVER.tar.xz
TARBALL_SHA256=87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953
MILOS_URL=https://github.com/milos-mainline/linux/commit
CATCRAFTS_URL=https://forgejo.catcrafts.net/Catcrafts/milos-linux/commit
QCOM_LINUX_URL=https://salsa.debian.org/Mobian-team/devices/kernels/qcom-linux.git
QCOM_LINUX_COMMIT=7a3790b18201f3fc3b7220d5d4297941579c3c65
# Hash abbreviation of the `index` lines, as in the published patches
ABBREV_milos=7
ABBREV_catcrafts=9

K=$(dirname "$(realpath "$0")")
[ $# -eq 1 ] || { echo "usage: $0 <work_dir>" >&2; exit 2; }
W=$(realpath -m "$1")
DL=$W/dl
SRC=$W/$SRCPKG-$KVER
[ ! -e "$SRC" ] || { echo "$SRC exists; remove it first" >&2; exit 1; }
mkdir -p "$DL/milos" "$DL/catcrafts"

# Fixed identity and dates: nothing here depends on who runs it, or when
export GIT_AUTHOR_NAME=regen GIT_AUTHOR_EMAIL=regen@invalid
export GIT_COMMITTER_NAME=regen GIT_COMMITTER_EMAIL=regen@invalid
export GIT_COMMITTER_DATE='2000-01-01T00:00:00+0000'
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

fetch() {   # url file
    [ -s "$2" ] && return 0
    curl -fsSL --retry 3 -o "$2.part" "$1"
    mv "$2.part" "$2"
}

echo "== downloads"
fetch "$TARBALL_URL" "$DL/linux-$KVER.tar.xz"
echo "$TARBALL_SHA256  $DL/linux-$KVER.tar.xz" | sha256sum -c --quiet
while read -r dir sha; do
    case $dir in
        milos) url=$MILOS_URL/$sha.patch ;;
        catcrafts) url=$CATCRAFTS_URL/$sha.patch ;;
        *) echo "upstream.txt: unknown directory $dir" >&2; exit 1 ;;
    esac
    fetch "$url" "$DL/$dir/$sha.patch"
done < "$K/upstream.txt"
if [ ! -d "$DL/qcom-linux/debian" ]; then
    rm -rf "$DL/qcom-linux"
    git init -q "$DL/qcom-linux"
    git -C "$DL/qcom-linux" fetch -q --depth 1 --filter=blob:none "$QCOM_LINUX_URL" "$QCOM_LINUX_COMMIT"
    git -C "$DL/qcom-linux" sparse-checkout set --no-cone '/debian/'
    git -C "$DL/qcom-linux" -c advice.detachedHead=false checkout -q FETCH_HEAD
fi
[ "$(git -C "$DL/qcom-linux" rev-parse HEAD)" = "$QCOM_LINUX_COMMIT" ]

echo "== patch series"
G=$W/git
rm -rf "$G"; mkdir -p "$G"
tar -C "$G" -xf "$DL/linux-$KVER.tar.xz"
cd "$G/linux-$KVER"
git init -q
git add -Af .
git commit -q -m "Linux $KVER"
OUT=$W/patches
rm -rf "$OUT"; mkdir -p "$OUT"
for dir in milos catcrafts; do
    base=$(git rev-parse HEAD)
    awk -v d="$dir" '$1 == d {print $2}' "$K/upstream.txt" | while read -r sha; do
        p=$DL/$dir/$sha.patch
        if [ -f "$K/fixups/$sha.diff" ]; then
            patch -s -o "$W/fixed.patch" "$p" < "$K/fixups/$sha.diff"
            p=$W/fixed.patch
        fi
        git am -q --keep-cr "$p" || { echo "git am failed: $dir $sha" >&2; exit 1; }
    done
    eval abbrev=\$ABBREV_$dir
    git format-patch -q --no-signature --abbrev="$abbrev" -o "$OUT/$dir" "$base..HEAD"
done
mkdir -p "$OUT/debian" "$OUT/mobian"
cp "$DL/qcom-linux/debian/patches/debian/"*.patch "$OUT/debian/"
cp "$DL/qcom-linux/debian/patches/mobian/"*.patch "$OUT/mobian/"
rm -f "$W/fixed.patch"

echo "== check against patches.sha256"
cd "$OUT"
[ "$(find . -name '*.patch' | wc -l)" -eq "$(wc -l < "$K/series")" ] ||
    { echo "patch count differs from series" >&2; exit 1; }
bad=0
while read -r want path; do
    got=$(tail -n +2 "$path" | sha256sum | cut -d' ' -f1)
    [ "$got" = "$want" ] || { echo "MISMATCH $path" >&2; bad=1; }
done < "$K/patches.sha256"
[ $bad = 0 ] || exit 1
echo "all $(wc -l < "$K/patches.sha256") patches match"

echo "== source package"
mkdir -p "$W/x"
tar -C "$W/x" -xf "$DL/linux-$KVER.tar.xz"
mv "$W/x/linux-$KVER" "$SRC"
rmdir "$W/x"
cp "$DL/linux-$KVER.tar.xz" "$W/${SRCPKG}_$KVER.orig.tar.xz"
cp -r "$DL/qcom-linux/debian" "$SRC/debian"
cd "$SRC"
for p in "$K"/packaging/*.patch; do
    patch -s -p1 -F0 --no-backup-if-mismatch < "$p"
done
rm -rf debian/patches
mkdir -p debian/patches
cp -r "$OUT/milos" "$OUT/catcrafts" "$OUT/debian" "$OUT/mobian" debian/patches/
cp "$K/series" debian/patches/series
cp "$K/milos.config" debian/config/milos.config
cp "$K/README.milos-linux" debian/README.milos-linux
rm -rf "$G"
echo "ready: $SRC"
