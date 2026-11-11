#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Replace a conflicted region of a file with the matching region of a reference copy.

Usage: splice-ref.py <file> <reference_file> <start_marker> <end_marker>
In <file>, the region runs from the first line containing <start_marker>
(searching from the first '<<<<<<<' line backwards to the nearest match is not
done: the region starts at the first '<<<<<<<' at or before the first marker
line) up to, but not including, the first line containing <end_marker>
after it. In the reference, the region runs from the first line containing
<start_marker> up to, but not including, <end_marker>.
"""
import sys

path, refp, start, end = sys.argv[1:5]
cur = open(path).read().split('\n')
ref = open(refp).read().split('\n')

c0 = next(i for i, l in enumerate(cur) if l.startswith('<<<<<<<'))
c1 = next(i for i in range(c0, len(cur)) if end in cur[i] and not cur[i].startswith(('<<<<<<<', '=======', '>>>>>>>')))
r0 = next(i for i, l in enumerate(ref) if start in l)
r1 = next(i for i in range(r0, len(ref)) if end in ref[i])

region = cur[c0:c1]
assert any(l.startswith('>>>>>>>') for l in region), 'region does not cover the whole conflict'
new = cur[:c0] + ref[r0:r1] + cur[c1:]
open(path, 'w').write('\n'.join(new))
left = sum(l.startswith('<<<<<<<') for l in new)
print(f'replaced lines {c0+1}-{c1} with reference lines {r0+1}-{r1}; {left} conflicts left')
