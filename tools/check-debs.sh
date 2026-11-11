#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Inspect the built kernel .debs: metadata, FP6 DTB, key modules, and re-run
# the fragment checks against the config the build actually used.
# Usage: check-debs.sh <pkg_dir> <kernel_tree> <milos.config> <reference_config>
#   reference_config: a config known to run on the phone (e.g. postmarketOS')
set -eu
P=$(realpath "$1"); TREE=$(realpath "$2"); FRAG=$(realpath "$3"); REF=$(realpath "$4")
TOOLS=$(dirname "$(realpath "$0")")
IMG=$(ls "$P"/linux-image-7.3-milos_*_arm64.deb)
X=$(mktemp -d /tmp/fp6-deb.XXXXXX)
dpkg-deb -x "$IMG" "$X"

echo "== packages"
for d in "$P"/*.deb; do echo "$(basename "$d")  $(du -h "$d" | cut -f1)"; done
echo; dpkg-deb -f "$IMG" Package Version Architecture Depends

KREL=$(ls "$X"/lib/modules 2>/dev/null || ls "$X"/usr/lib/modules)
echo; echo "== kernel release: $KREL"
ls -la "$X"/boot/ | sed -n '2,20p'

echo; echo "== FP6 DTB"
find "$X" -name 'milos-fairphone-fp6.dtb' -exec ls -la {} \;

echo; echo "== key modules (mic, speakers, cameras, sensors, NFC, panel, touch, modem, wifi)"
MODDIR=$(find "$X" -type d -path "*/modules/$KREL" | head -1)
for m in snd-soc-wcd9378 snd-soc-wcd9378-sdw snd-soc-aw88261 snd-soc-sc8280xp imx896 dw9784 ov13b10 \
         qcom-camss inv-icm42600-spi dps310 stk3310 qmc6308 s3fwrn5-i2c panel-novatek-nt37705 \
         eswin_eph8621 ipa ath11k_ahb qcom_q6v5_pas msm qcom-ice; do
    f=$(find "$MODDIR" -name "$m.ko*" | head -1)
    printf '%-24s %s\n' "$m" "${f:+$(basename "$f")}${f:-MISSING}"
done

echo; echo "== fragment check against the config the build used"
CFG=$(ls "$X"/boot/config-*)
python3 -I "$TOOLS/fragcheck.py" "$TREE" "$FRAG" "$CFG" "$REF" \
    | sed -n '/## DROPPED/,/changed/p'
grep -E '^CONFIG_RUST=|^# CONFIG_RUST is not set|^CONFIG_RD_ZSTD=|^CONFIG_SND_SOC_WCD9378_SDW=|^CONFIG_SCSI_UFS_CRYPTO=' "$CFG"
rm -rf "$X"
