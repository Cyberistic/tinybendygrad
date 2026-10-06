#!/usr/bin/env python3
"""Apply-check `.agents/slop/agendop2/REPLACEMENTS.md` with the file's own trivial rule.

Splits on level-`### ` headings, then reads fences whose info string is exactly `OLD` / `NEW`.
Asserts each OLD is a byte-for-byte substring of `AGENTS.md` counting exactly once, and that the
NEW does not itself still contain the OLD (so the replacement is a real patch and cannot re-fire).
Reads `AGENTS.md` READ-ONLY; writes nothing.
"""
import re

md = open('.agents/slop/agendop2/REPLACEMENTS.md').read()
agents = open('AGENTS.md').read()

chunks = re.split(r'(?m)^### ', md)[1:]
pairs = []
for ch in chunks:
    title = ch.splitlines()[0].strip()
    old_m = re.search(r'```OLD\n(.*?)\n```', ch, re.S)
    new_m = re.search(r'```NEW\n(.*?)\n```', ch, re.S)
    assert old_m and new_m, f'heading {title!r}: fence parse failed'
    pairs.append((title, old_m.group(1), new_m.group(1)))

print(f'pairs parsed: {len(pairs)}')
ok = 0
for title, old, new in pairs:
    c = agents.count(old)
    re_fires = old in new
    verdict = 'VERIFIED count==1' if (c == 1 and not re_fires) else 'FAILED'
    if verdict == 'VERIFIED count==1':
        ok += 1
    print(f'  [{verdict}] {title}  count={c}  old-in-new={re_fires}')
print(f'verified: {ok}/{len(pairs)}')
