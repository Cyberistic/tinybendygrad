#!/usr/bin/env python3
"""ASSERT the ledger FILE equals what `naming-gate-ledger.py` WOULD write.

    python3 .agents/slop/naming-gate-ledger-check.py

WHY THIS IS A FILE. The gate reads the ledger FILE; the generator WRITES the
ledger FILE. Nothing in either connected the two, so a hand-edited line and the
RULES table can drift apart silently -- and the drift is invisible from the gate's
own output, because the gate never consults RULES. Concretely: adding a line by
hand keeps the gate green while the next `naming-gate-ledger.py` run silently
DELETES it, and the gate then goes red with no edit to point at.

It also makes a hand edit SAFE to make. Regenerating is not: the generator rewrites
all 668 lines from the live census, and other units are mid-write, so a regeneration
taken at the wrong moment drops lines for transient candidates and leaves the ledger
permanently wrong. So the rule is: hand-place the line in `sorted()` position, then
PROVE it here.

Read-only. It writes nothing and patches nothing.
"""
import difflib
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    ng = load('ng', os.path.join(HERE, 'naming-gate.py'))
    gen = load('ngl', os.path.join(HERE, 'naming-gate-ledger.py'))

    _, candidates, _ = ng.census()
    detected = {(rel, name, affix): stem
                for (rel, name), hits in candidates.items()
                for affix, stem in hits}

    reason, dead = {}, []
    for rel, pattern, why in gen.RULES:
        rx = re.compile(pattern)
        if not any(f == rel and rx.fullmatch(a) for (f, _, a) in detected):
            dead.append('%s / %s' % (rel, pattern))
        for key in sorted(detected):
            if key[0] == rel and key not in reason and rx.fullmatch(key[2]):
                reason[key] = why

    expected = gen.HEADER + ''.join(
        '%s\t%s\t%s\t%s\n' % (k[0], k[1], k[2], reason[k]) for k in sorted(reason))
    actual = open(ng.LEDGER).read()

    fails = []
    if dead:
        fails.append('DEAD RULE(S) -- match nothing live: %s' % ', '.join(dead))
    uncovered = sorted(k for k in detected if k not in reason)
    if uncovered:
        fails.append('UNCOVERED RENAME(S):\n'
                     + '\n'.join('  %s :: %s  +%s' % k for k in uncovered))
    if expected != actual:
        diff = list(difflib.unified_diff(actual.splitlines(True), expected.splitlines(True),
                                         'on-disk ledger', 'generator output', n=1))
        fails.append('LEDGER DIFFERS from the generator (%d diff lines):\n%s'
                     % (len(diff), ''.join(diff[:40])))

    print('detected rename proposals : %d' % len(detected))
    print('rules matching live       : %d of %d' % (len(gen.RULES) - len(dead), len(gen.RULES)))
    print('ledger lines on disk      : %d'
          % sum(1 for l in actual.splitlines() if l and not l.startswith('#')))
    print()
    if fails:
        for f in fails:
            print('FAIL  ' + f)
        return 1
    print('ok   the ledger on disk is exactly what naming-gate-ledger.py would write')
    print('ok   every live proposal is covered, and no rule is dead weight')
    return 0


if __name__ == '__main__':
    sys.exit(main())