#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Static comparison of Mobian kconfig fragments against a known-good resolved config.

Usage:
  cfgdiff.py <config_dir> <device_fragment_name> <reference_full_config>

<config_dir> holds debian.config, debian.arm64.config, mobian.config and the
device fragment (e.g. milos.config), concatenated in that order by debian/rules.
No Kconfig resolution is done: the output is a candidate list to review, not
a final answer.
"""
import re
import sys
from pathlib import Path

SET_RE = re.compile(r'^(CONFIG_[A-Za-z0-9_]+)=(.*)$')
UNSET_RE = re.compile(r'^# (CONFIG_[A-Za-z0-9_]+) is not set$')


def parse(path):
    vals = {}
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        m = SET_RE.match(line)
        if m:
            v = m.group(2)
            vals[m.group(1)] = 'n' if v == 'n' else v
            continue
        m = UNSET_RE.match(line)
        if m:
            vals[m.group(1)] = 'n'
    return vals


# Symbols that look hardware/SoC/board specific (what a device fragment should carry)
HW = re.compile(
    r'QCOM|MILOS|_SM_|^CONFIG_SM_|QRTR|RPMSG|REMOTEPROC|SND_SOC|SOUNDWIRE|VIDEO_|'
    r'TOUCHSCREEN|PANEL|DRM_MSM|PHY_|INTERCONNECT|PINCTRL|REGULATOR|NFC|IIO|'
    r'INV_ICM|DPS310|STK3310|AK09|MMC|UFS|ATH11K|BT_|WCN|TYPEC|UCSI|PMIC|BATTERY|'
    r'CHARGER|LEDS_|INPUT_|HAPTIC|SPMI|THERMAL|IPA|RMNET|CAMSS|IRIS|ADRENO|GPU|'
    r'FASTRPC|HWSPINLOCK|MAILBOX|IOMMU|ARM_SMMU|GENI|SPI|I2C|USB_DWC3|EUSB2|NVMEM|'
    r'DW97|IMX|OV13|VL53|AW8|ESWIN|NT37|S3FWRN|POWER_SEQ|CPUFREQ|DEVFREQ|EXTCON'
)


def main():
    cfgdir, frag, ref = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
    order = ['debian.config', 'debian.arm64.config', 'mobian.config']
    layers = {name: parse(cfgdir / name) for name in order}
    dev = parse(cfgdir / frag)
    refv = parse(ref)

    base = {}
    for name in order:
        base.update(layers[name])

    redundant, overrides = [], []
    for k, v in dev.items():
        if k in base:
            if base[k] == v:
                redundant.append(k)
            else:
                src = next(n for n in reversed(order) if k in layers[n])
                overrides.append((k, base[k], v, src))

    merged = dict(base)
    merged.update(dev)

    missing = []
    for k, v in refv.items():
        if v in ('y', 'm') and merged.get(k, 'n') == 'n' and HW.search(k):
            missing.append((k, v))

    print(f'# device fragment: {frag}: {len(dev)} symbols')
    print(f'#   redundant (same value already set by debian/mobian layers): {len(redundant)}')
    print(f'#   overrides of debian/mobian layer values: {len(overrides)}')
    print(f'#   hw-looking symbols y/m in reference but not enabled by any fragment: {len(missing)}')
    print('\n## OVERRIDES (fragment wins because it is concatenated last)')
    for k, b, v, src in sorted(overrides):
        print(f'{k}: {src}={b} -> {frag}={v}')
    print('\n## REDUNDANT')
    print(' '.join(sorted(redundant)))
    print('\n## MISSING vs reference (candidates only; many may be pulled by defaults/select)')
    for k, v in sorted(missing):
        print(f'{k}={v}')


if __name__ == '__main__':
    main()
