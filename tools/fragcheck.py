#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Validate a resolved (olddefconfig'd) Mobian config.

Usage: fragcheck.py <kernel_tree> <device_fragment> <resolved_config> <reference_config>

1. DROPPED: symbols the device fragment asked for whose resolved value differs
   (unmet dependency, undefined symbol, y demoted to m, ...).
2. MISSING: hardware-looking symbols that are y/m in the reference (a config
   known to run on the device) but off in ours; split by whether the symbol
   exists in this tree at all (if not, it is a driver from the reference's
   extra patches).
3. Spot checks of options that are known to matter for booting Debian.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cfgdiff import parse, HW  # noqa: E402


def defined_symbols(tree):
    syms = set()
    rx = re.compile(r'^\s*(?:menu)?config\s+([A-Za-z0-9_]+)', re.M)
    for p in Path(tree).rglob('Kconfig*'):
        try:
            syms.update(rx.findall(p.read_text(errors='replace')))
        except OSError:
            pass
    return syms


def norm(v):
    return 'n' if v in (None, 'n') else v


def main():
    tree, frag, resolved, ref = sys.argv[1:5]
    defined = defined_symbols(tree)
    want, got, refv = parse(frag), parse(resolved), parse(ref)

    print(f'# fragment {frag}: {len(want)} symbols; resolved {resolved}')
    print('\n## DROPPED / CHANGED by Kconfig (requested -> resolved)')
    n = 0
    for k, v in sorted(want.items()):
        r = norm(got.get(k))
        if norm(v) != r:
            n += 1
            tag = '' if k.removeprefix('CONFIG_') in defined else '  [symbol not defined in this tree]'
            print(f'{k}: {v} -> {r}{tag}')
    print(f'# {n} changed')

    print('\n## MISSING vs reference: hw-looking, y/m in reference, off here')
    in_tree, not_in_tree = [], []
    for k, v in sorted(refv.items()):
        if v in ('y', 'm') and norm(got.get(k)) == 'n' and HW.search(k):
            (in_tree if k.removeprefix('CONFIG_') in defined else not_in_tree).append(f'{k}={v}')
    print(f'# defined in this tree ({len(in_tree)}):')
    print('\n'.join(in_tree))
    print(f'# NOT defined in this tree, i.e. reference-only patches ({len(not_in_tree)}):')
    print('\n'.join(not_in_tree))

    print('\n## SPOT CHECKS')
    for k in ['CONFIG_RD_GZIP', 'CONFIG_RD_ZSTD', 'CONFIG_RD_XZ', 'CONFIG_BLK_DEV_INITRD',
              'CONFIG_FW_LOADER_COMPRESS_XZ', 'CONFIG_FW_LOADER_COMPRESS_ZSTD',
              'CONFIG_DEVTMPFS', 'CONFIG_EXT4_FS', 'CONFIG_SCSI_UFS_QCOM', 'CONFIG_PHY_QCOM_QMP_UFS',
              'CONFIG_PINCTRL_MILOS', 'CONFIG_SM_GCC_MILOS', 'CONFIG_INTERCONNECT_QCOM_MILOS',
              'CONFIG_DRM_MSM', 'CONFIG_DRM_PANEL_NOVATEK_NT37705', 'CONFIG_TOUCHSCREEN_ESWIN_EPH8621',
              'CONFIG_QRTR', 'CONFIG_QRTR_SMD', 'CONFIG_QCOM_PD_MAPPER', 'CONFIG_QCOM_Q6V5_PAS',
              'CONFIG_ATH11K_AHB', 'CONFIG_QCOM_IPA', 'CONFIG_RMNET', 'CONFIG_SND_SOC_SC8280XP',
              'CONFIG_SND_SOC_AW88261', 'CONFIG_PANIC_TIMEOUT', 'CONFIG_EFI', 'CONFIG_PCI',
              'CONFIG_VT', 'CONFIG_FRAMEBUFFER_CONSOLE', 'CONFIG_DRM_SIMPLEDRM',
              'CONFIG_UEVENT_HELPER', 'CONFIG_DEVTMPFS_MOUNT']:
        print(f'{k}: ours={norm(got.get(k))} ref={norm(refv.get(k))}')


if __name__ == '__main__':
    main()
