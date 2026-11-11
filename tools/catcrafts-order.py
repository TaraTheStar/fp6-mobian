#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Order the non-merge commits of a Forgejo compare (base...tip) topologically.

Usage: catcrafts-order.py <compare.json>
Prints "<sha> <subject>" lines, parents before children. Among commits that are
ready at the same time, older committer date first, which keeps each topic
branch roughly contiguous and in its original order.
"""
import json
import sys

data = json.load(open(sys.argv[1]))
commits = {c['sha']: c for c in data['commits']}
inset = set(commits)

pending = {s: {p['sha'] for p in c['parents'] if p['sha'] in inset} for s, c in commits.items()}
children = {s: [] for s in commits}
for s, ps in pending.items():
    for p in ps:
        children[p].append(s)

date = lambda s: commits[s]['commit']['committer']['date']
ready = sorted([s for s, ps in pending.items() if not ps], key=date)
order = []
while ready:
    s = ready.pop(0)
    order.append(s)
    for ch in children[s]:
        pending[ch].discard(s)
        if not pending[ch]:
            ready.append(ch)
    ready.sort(key=date)

assert len(order) == len(commits), 'cycle or missing commits'
for s in order:
    c = commits[s]
    if len(c['parents']) > 1:
        continue
    print(s, c['commit']['message'].split('\n')[0])
