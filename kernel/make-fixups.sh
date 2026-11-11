#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Work out the fix-ups regen.sh needs: for each Catcrafts patch, in series
# order, whether the upstream patch applies with `git am` where the linear
# series puts it, and lands exactly as the published patch does. Where it
# doesn't, write fixups/<sha>.diff, a diff from the upstream patch to one with
# the same header and the published patch's diff (the rebase that made the
# series resolved those hunks by context; the content is unchanged).
#
# Usage: kernel/make-fixups.sh <work_dir> <published_patches_dir>
#   work_dir: a regen.sh work directory (its dl/ is used)
#   published_patches_dir: holds milos/ and catcrafts/ as listed in series
set -eu

KVER=7.3
K=$(dirname "$(realpath "$0")")
W=$(realpath "$1"); PUB=$(realpath "$2"); DL=$W/dl
export GIT_AUTHOR_NAME=regen GIT_AUTHOR_EMAIL=regen@invalid
export GIT_COMMITTER_NAME=regen GIT_COMMITTER_EMAIL=regen@invalid
export GIT_COMMITTER_DATE='2000-01-01T00:00:00+0000'
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

body() { sed -n '/^diff --git /,$p' "$1"; }

G=$W/fixups-git
rm -rf "$G"; mkdir -p "$G"
tar -C "$G" -xf "$DL/linux-$KVER.tar.xz"
cd "$G/linux-$KVER"
git init -q; git add -Af .; git commit -q -m "Linux $KVER"
awk '$1 == "milos" {print $2}' "$K/upstream.txt" | while read -r sha; do
    git am -q --keep-cr "$DL/milos/$sha.patch"
done

rm -f "$K"/fixups/*.diff
mkdir -p "$K/fixups"
i=0
grep '^catcrafts/' "$K/series" | while read -r pub; do
    i=$((i + 1))
    sha=$(awk '$1 == "catcrafts" {print $2}' "$K/upstream.txt" | sed -n "${i}p")
    up=$DL/catcrafts/$sha.patch
    if git am -q --keep-cr "$up" >/dev/null 2>&1 &&
       git format-patch -1 --stdout --no-signature --abbrev=9 HEAD > "$W/got.patch" &&
       [ "$(body "$W/got.patch")" = "$(body "$PUB/$pub")" ]; then
        continue
    fi
    git am --abort 2>/dev/null || git reset -q --hard HEAD~1
    { sed '/^diff --git /,$d' "$up"; body "$PUB/$pub"; } > "$W/want.patch"
    diff -u --label "a/$sha.patch" --label "b/$sha.patch" "$up" "$W/want.patch" \
        > "$K/fixups/$sha.diff" || true
    git am -q --keep-cr "$W/want.patch"
    echo "fix-up: $pub"
done
rm -rf "$G" "$W/got.patch" "$W/want.patch"
echo "$(ls "$K"/fixups/*.diff 2>/dev/null | wc -l) fix-ups in $K/fixups"
