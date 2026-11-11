#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""For every compatible string in the given DTS/DTSI files, find the kernel
driver that matches it and report whether the resolved config builds it.

Usage: dt-driver-check.py <kernel_tree> <resolved_config> <dts> [<dts> ...]

Method: find .c files under drivers/, sound/, net/ containing the compatible as
a quoted literal; map each file to the CONFIG symbol that builds it via the
`obj-$(CONFIG_X) += name.o` / `name-objs`/`name-y` lines of its Makefile.
A compatible is OK if at least one matching driver's symbol is y or m.
Only the first compatible of each list matters to the kernel, but fallbacks are
reported too, so a list is OK if any member is covered.
Static text analysis only: nothing from the tree is executed.
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

tree = Path(sys.argv[1])
cfg = {}
for l in Path(sys.argv[2]).read_text().splitlines():
    m = re.match(r'(CONFIG_\w+)=(.*)', l)
    if m:
        cfg[m.group(1)] = m.group(2)

# compatibles grouped per node (one `compatible = ...;` statement each)
lists = []
for dts in sys.argv[3:]:
    txt = Path(dts).read_text()
    txt = re.sub(r'/\*.*?\*/', '', txt, flags=re.S)
    for m in re.finditer(r'compatible\s*=\s*((?:"[^"]*"\s*,?\s*)+);', txt):
        lists.append((Path(dts).name, re.findall(r'"([^"]*)"', m.group(1))))

wanted = {c for _, cs in lists for c in cs}

# index driver sources by compatible literal
files_for = defaultdict(set)
lit = re.compile(r'"([a-z0-9,._+-]+)"')
for top in ('drivers', 'sound', 'net', 'kernel'):
    for p in (tree / top).rglob('*.c'):
        try:
            t = p.read_text(errors='replace')
        except OSError:
            continue
        if 'compatible' not in t:
            continue
        for c in set(lit.findall(t)) & wanted:
            files_for[c].add(p)

# map object file -> CONFIG symbol, per directory, following composite objects
mk_cache = {}


def symbols_for(src):
    d = src.parent
    if d not in mk_cache:
        rules = defaultdict(set)   # objname -> {CONFIG}
        parts = defaultdict(set)   # composite -> {member objs}
        mk = d / 'Makefile'
        if mk.exists():
            text = mk.read_text(errors='replace').replace('\\\n', ' ')
            for line in text.splitlines():
                m = re.match(r'\s*obj-\$\((CONFIG_\w+)\)\s*[:+]?=\s*(.*)', line)
                if m:
                    for o in m.group(2).split():
                        rules[o].add(m.group(1))
                m = re.match(r'\s*([\w-]+)-(?:objs|y)\s*[:+]?=\s*(.*)', line)
                if m:
                    for o in m.group(2).split():
                        parts[o].add(m.group(1) + '.o')
                m = re.match(r'\s*([\w-]+)-\$\((CONFIG_\w+)\)\s*[:+]?=\s*(.*)', line)
                if m and m.group(1) not in ('obj', 'ccflags', 'subdir'):
                    for o in m.group(3).split():
                        parts[o].add(m.group(1) + '.o')
                        rules.setdefault(o, set()).add(m.group(2))
        mk_cache[d] = (rules, parts)
    rules, parts = mk_cache[d]
    obj = src.stem + '.o'
    syms, todo, seen = set(), [obj], set()
    while todo:
        o = todo.pop()
        if o in seen:
            continue
        seen.add(o)
        syms |= rules.get(o, set())
        todo += list(parts.get(o, ()))
    return syms


ok, bad, nodrv = [], [], []
for where, cs in lists:
    covered, found_any, details = False, False, []
    for c in cs:
        for src in sorted(files_for.get(c, ())):
            found_any = True
            syms = symbols_for(src) or {'?'}
            vals = {s: cfg.get(s, 'n') for s in syms}
            details.append(f'{c} -> {src.relative_to(tree)} {vals}')
            if any(v in ('y', 'm') for v in vals.values()):
                covered = True
    line = f'{where}: {", ".join(cs)}'
    if covered:
        ok.append(line)
    elif found_any:
        bad.append(line + '\n      ' + '\n      '.join(details))
    else:
        nodrv.append(line)

print(f'## NOT BUILT: a driver exists but its symbol is off ({len(bad)})')
print('\n'.join(bad) or '(none)')
print(f'\n## NO DRIVER FOUND for any compatible in the list ({len(nodrv)})')
print('\n'.join(sorted(set(nodrv))) or '(none)')
print(f'\n## OK ({len(ok)} compatible statements covered)')
