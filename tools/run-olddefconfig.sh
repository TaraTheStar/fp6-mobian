#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Resolve Mobian-style layered kconfig fragments with olddefconfig inside a
# network-less container. The kernel source is mounted read-only; only the
# per-variant output directory is writable.
#
# Usage: run-olddefconfig.sh <kernel_src> <layers_dir> <out_dir> [device_fragment]
#   layers_dir: holds debian.config, debian.arm64.config, mobian.config
#   device_fragment: optional path to the device fragment (concatenated last,
#                    exactly like debian/rules does)
set -eu

SRC=$(realpath "$1")
LAYERS=$(realpath "$2")
OUT=$3
FRAG=${4:-}

mkdir -p "$OUT"
OUT=$(realpath "$OUT")

if [ -n "$FRAG" ]; then
    cat "$LAYERS/debian.config" "$LAYERS/debian.arm64.config" "$LAYERS/mobian.config" "$FRAG" > "$OUT/.config"
else
    cat "$LAYERS/debian.config" "$LAYERS/debian.arm64.config" "$LAYERS/mobian.config" > "$OUT/.config"
fi
cp "$OUT/.config" "$OUT/input.config"

podman run --rm --network=none --userns=keep-id \
    -v "$SRC:/src:ro" -v "$OUT:/out" \
    localhost/fp6-kconfig:forky \
    make -s -C /src O=/out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig \
    > "$OUT/olddefconfig.log" 2>&1 || { echo "FAILED, see $OUT/olddefconfig.log"; tail -20 "$OUT/olddefconfig.log"; exit 1; }

echo "resolved: $OUT/.config ($(grep -c '^CONFIG_' "$OUT/.config") set symbols)"
grep -i "warning" "$OUT/olddefconfig.log" | sort | uniq -c | sort -rn | head -20 || true
