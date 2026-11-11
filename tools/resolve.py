#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Resolve the Nth conflict block in a file.

Usage: resolve.py <file> <index> <mode> [separator]
  mode: ours | theirs | ours+theirs | theirs+ours
  separator: text inserted between the two sides for the combined modes,
             with \\n and \\t escapes (e.g. '\\t};\\n\\n' to close a DT node)
Index counts from 0 among the conflicts currently in the file.
"""
import re
import sys

path, idx, mode = sys.argv[1], int(sys.argv[2]), sys.argv[3]
sep = sys.argv[4].encode().decode('unicode_escape') if len(sys.argv) > 4 else ''
text = open(path).read()
rx = re.compile(r'<<<<<<< [^\n]*\n(.*?)(?:\|\|\|\|\|\|\| [^\n]*\n.*?)?=======\n(.*?)>>>>>>> [^\n]*\n', re.S)
blocks = list(rx.finditer(text))
m = blocks[idx]
ours, theirs = m.group(1), m.group(2)
rep = {'ours': ours, 'theirs': theirs,
       'ours+theirs': ours + sep + theirs, 'theirs+ours': theirs + sep + ours}[mode]
open(path, 'w').write(text[:m.start()] + rep + text[m.end():])
print(f'{path}: resolved conflict {idx} ({mode}); {len(blocks) - 1} left')
