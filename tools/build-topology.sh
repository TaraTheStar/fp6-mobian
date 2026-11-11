#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Build the Fairphone (Gen. 6) AudioReach topology from Catcrafts'
# audioreach-topology source, in a network-less container, and check the
# result against the pinned hash. The binary is not kept in git: it is built
# here and picked up by fp6-mobian-support's package build.
#
# Usage: tools/build-topology.sh [output_file]
set -eu

REPO=https://forgejo.catcrafts.net/Catcrafts/audioreach-topology.git
BRANCH=fp6
COMMIT=76e10781fcc16a3fd8dfd0278ad9dc307ed29871
SHA256=b799d001cf0da889f92215a6ef5143bda54021f5f76fa3e2e5d3797a169d7aa0
NAME=MILOS-Fairphone-Gen6-tplg.bin

HERE=$(dirname "$(realpath "$0")")
OUT=${1:-$HERE/../packaging/fp6-mobian-support/audio/$NAME}

W=$(mktemp -d /tmp/fp6-tplg.XXXXXX)
trap 'rm -rf "$W"' EXIT INT TERM

git clone -q --single-branch --branch "$BRANCH" "$REPO" "$W/src"
git -C "$W/src" -c advice.detachedHead=false checkout -q "$COMMIT"
mkdir "$W/build"

podman build -q -t fp6-tplg:forky -f "$HERE/Containerfile.tplg" "$HERE" >/dev/null
# The other boards' topologies are built too; some of them log ALSA errors
# without failing. Only ours is checked.
podman run --rm --network=none --userns=keep-id \
    -v "$W/src:/src:ro" -v "$W/build:/build" -w /build fp6-tplg:forky \
    sh -c 'cmake /src >cmake.log 2>&1 && make >make.log 2>&1' \
    || { tail -20 "$W/build/make.log" "$W/build/cmake.log" 2>/dev/null; exit 1; }

BIN=$W/build/qcom/milos/$NAME
echo "$SHA256  $BIN" | sha256sum -c --quiet
install -D -m644 "$BIN" "$OUT"
echo "built and verified: $OUT"
