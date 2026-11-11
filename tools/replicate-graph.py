#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Rebuild a Forgejo commit range (base...tip, merges included) in a local repo.

Usage: replicate-graph.py <repo> <base_ref> <compare.json> <patch_dir> <merge_dir> <map_out>

- non-merge commit: check out the local copy of its parent, `git am` its .patch
  (patch file found by the 10-char sha in its name)
- merge commit: check out the local copy of its first parent, apply the merge's
  diff against that parent (<merge_dir>/<sha>.diff), and record a commit with
  the local copies of all parents
Writes "<upstream_sha> <local_sha>" lines to map_out. Reads only data files;
the only program run is git.
"""
import json
import subprocess
import sys
from pathlib import Path

repo, base, cmp_json, pdir, mdir, map_out = sys.argv[1:7]
ENV = ['-c', 'user.name=replica', '-c', 'user.email=replica@localhost']


def git(*a, inp=None, env_extra=None):
    import os
    env = dict(os.environ, **(env_extra or {}))
    r = subprocess.run(['git', *ENV, *a], cwd=repo, input=inp, capture_output=True, text=True, env=env)
    if r.returncode:
        raise SystemExit(f'git {" ".join(a)} failed:\n{r.stdout}\n{r.stderr}')
    return r.stdout.strip()


data = json.load(open(cmp_json))
commits = {c['sha']: c for c in data['commits']}
inset = set(commits)
pending = {s: [p['sha'] for p in c['parents']] for s, c in commits.items()}

# topo order: Kahn, committer-date tie break
deps = {s: {p for p in ps if p in inset} for s, ps in pending.items()}
date = lambda s: commits[s]['commit']['committer']['date']
order, ready = [], sorted([s for s, d in deps.items() if not d], key=date)
while ready:
    s = ready.pop(0)
    order.append(s)
    for t, d in deps.items():
        if s in d:
            d.discard(s)
            if not d:
                ready.append(t)
    ready.sort(key=date)

base_local = git('rev-parse', base)
local = {}
patches = {p.name.split('-')[1].removesuffix('.patch'): p for p in Path(pdir).glob('*.patch')}


def loc(sha):
    return local[sha] if sha in local else base_local  # parents outside the range == base


for s in order:
    c = commits[s]
    parents = pending[s]
    msg = c['commit']['message']
    git('checkout', '-q', '--detach', loc(parents[0]))
    if len(parents) == 1:
        git('am', '-q', '--keep-cr', str(patches[s[:10]]))
    else:
        diff = Path(mdir, f'{s}.diff').read_text()
        if diff.strip():
            git('apply', '--index', '-', inp=diff)
        tree = git('write-tree')
        pargs = sum((['-p', loc(p)] for p in parents), [])
        new = git('commit-tree', tree, *pargs, inp=msg)
        git('checkout', '-q', '--detach', new)
    local[s] = git('rev-parse', 'HEAD')
    print(f'{s[:10]} -> {local[s][:10]} {"MERGE " if len(parents) > 1 else ""}{msg.splitlines()[0][:70]}')

Path(map_out).write_text(''.join(f'{s} {local[s]}\n' for s in order))
tip = data['commits'][0]['sha']  # Forgejo lists newest first
git('branch', '-f', 'replica', local[tip])
print(f'replica tip: {local[tip]}')
