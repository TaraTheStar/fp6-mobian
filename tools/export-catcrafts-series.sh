#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Linearize Catcrafts' combined-stable (a merge of topic branches on top of
# milos-mainline v7.3.0-milos) into an ordered quilt-style patch series, as
# Mobian's qcom-linux packaging carries community trees in debian/patches/<name>/.
#
# Then prove the linearization is faithful: apply the series with `git am` on a
# scratch branch at the base and diff the resulting tree against combined-stable.
# Any leftover diff is content that only exists in merge commits (conflict
# resolutions) and must become an extra patch.
#
# Usage: export-catcrafts-series.sh <git_repo> <out_dir> [base] [tip]
set -eu

REPO=$(realpath "$1")
OUT=$2
BASE=${3:-v7.3.0-milos}
TIP=${4:-combined-stable}

mkdir -p "$OUT"
OUT=$(realpath "$OUT")
rm -f "$OUT"/*.patch "$OUT"/series "$OUT"/merge-residue.diff

cd "$REPO"
# --topo-order --reverse: parents before children, each topic branch kept contiguous
# where possible; --no-merges: merges carry no changes unless they resolved conflicts
git format-patch -q --no-merges --topo-order -o "$OUT" "$BASE..$TIP"
( cd "$OUT" && ls -1 *.patch ) > "$OUT/series"
echo "exported $(wc -l < "$OUT/series") patches"

# Verify on a throwaway worktree
WT=$(mktemp -d /tmp/catcrafts-verify.XXXXXX)
git worktree add -q --detach "$WT" "$BASE"
cd "$WT"
if git -c user.name=verify -c user.email=verify@localhost am -q --keep-cr "$OUT"/*.patch; then
    echo "all patches apply cleanly on $BASE"
else
    echo "git am FAILED at: $(git am --show-current-patch=diff 2>/dev/null | head -1 || true)"
    ls .git 2>/dev/null >/dev/null || true
    git am --abort || true
    cd "$REPO" && git worktree remove --force "$WT"
    exit 1
fi
git diff --stat HEAD "$TIP" | tail -1
git diff HEAD "$TIP" > "$OUT/merge-residue.diff"
if [ -s "$OUT/merge-residue.diff" ]; then
    echo "RESIDUE: linearized tree differs from $TIP (see merge-residue.diff)"
else
    echo "IDENTICAL: linearized series reproduces $TIP exactly"
    rm "$OUT/merge-residue.diff"
fi
cd "$REPO" && git worktree remove --force "$WT"
