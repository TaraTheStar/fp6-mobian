#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""For each CONFIG_ symbol, report whether it is defined in a kernel tree (or in
patch files that add Kconfig entries) and show its default/select-ers.

Usage: kdefault.py <kernel_tree> <patch_dir> SYMBOL [SYMBOL ...]
Reads files only; runs nothing from the tree.
"""
import re
import sys
from pathlib import Path


def kconfig_texts(tree, patchdir):
    for p in Path(tree).rglob('Kconfig*'):
        if '/debian/' in str(p) or '/.git/' in str(p):
            continue
        try:
            yield str(p.relative_to(tree)), p.read_text(errors='replace')
        except OSError:
            pass
    # Kconfig hunks added by patches: keep only '+' lines of Kconfig files
    for p in sorted(Path(patchdir).rglob('*.patch')):
        cur = None
        buf = []
        for line in p.read_text(errors='replace').splitlines():
            if line.startswith('+++ '):
                if cur and buf:
                    yield f'{p.name}:{cur}', '\n'.join(buf)
                cur = line[4:] if 'Kconfig' in line else None
                buf = []
            elif cur and line.startswith('+') and not line.startswith('+++'):
                buf.append(line[1:])
        if cur and buf:
            yield f'{p.name}:{cur}', '\n'.join(buf)


def main():
    tree, patchdir, syms = sys.argv[1], sys.argv[2], [s.removeprefix('CONFIG_') for s in sys.argv[3:]]
    texts = list(kconfig_texts(tree, patchdir))
    for s in syms:
        defs, selected_by = [], []
        for name, txt in texts:
            m = re.search(rf'^\s*(?:menu)?config {s}\n((?:[ \t].*\n|\n)*)', txt + '\n', re.M)
            if m:
                body = m.group(1)
                d = [l.strip() for l in body.splitlines() if re.match(r'\s*(default|def_bool|def_tristate|depends on)\b', l)]
                defs.append((name, d))
            for blk in re.finditer(rf'^\s*(?:menu)?config (\w+)\n((?:[ \t].*\n|\n)*)', txt + '\n', re.M):
                if re.search(rf'^\s*(select|imply) {s}\b', blk.group(2), re.M):
                    selected_by.append(blk.group(1))
        if not defs:
            print(f'CONFIG_{s}: NOT DEFINED in tree or patches')
            continue
        for name, d in defs:
            print(f'CONFIG_{s}: [{name}] {"; ".join(d) or "(no default -> n)"}')
        if selected_by:
            print(f'    selected/implied by: {" ".join(sorted(set(selected_by))[:8])}')


if __name__ == '__main__':
    main()
