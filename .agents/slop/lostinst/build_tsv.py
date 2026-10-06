#!/usr/bin/env python
"""Emit .agents/slop/lostinst/INSTRUMENTS.tsv from census.json + curated claims."""
import json, csv

recs = json.load(open('.agents/slop/lostinst/census.json'))

CLAIM = {
 '.agents/slop/cstyle-shapes-selftest.py':
   'TOOLS.md:1208 — "One control per row shape ... each run ARMED and RED, each run TWICE, plus a DISARM lane" (the cstyle gate\'s plant can go RED). Cited by live cstyle-gate.py:192, reader-guard.py:164.',
 '.agents/slop/e2e_gpu_probe.mjs':
   'TOOLS.md:703 — "is there a device that [renders]"; TODO.md:5175 "THE ADAPTER IS PROBED, NOT ASSUMED". EXEC-referenced by live e2e_negctl.sh:48.',
 '.agents/slop/fold-rng-mutate.py':
   'TOOLS.md:731 / TODO.md:852 — "19 mutations of the ranges fold ... 15 move rows, and all 4 zeros are [justified]".',
 '.agents/slop/ga_mutate.py':
   'TOOLS.md:575 — "41 one-token mutations of renderer/amd/generate.bend: 40 move gate rows". Named by live zero-audit.py:49, table-pin.py:61.',
 '.agents/slop/mixin-op-mutate.py':
   'TOOLS.md:50 — "17 one-token mutations of mixin/op.bend ... 4 of 17 are zero".',
 '.agents/slop/nn-init-mutate.py':
   'TOOLS.md:53 — one-token mutations of the nn/ files, nn-init M14 = whitespace CONTROL.',
 '.agents/slop/pin-tables.py':
   'TOOLS.md:1177 — "WRITES the pin into each table ... A pin is a claim about a run". Tables in the tree still read "Written by pin-tables.py, 2026-10-04".',
 '.agents/slop/rf2-mutate.py':
   'TOOLS.md:319 — the rf2 mutation table; named by live zero-audit.py:67, table-pin.py:67, formblind-census.py:114.',
 '.agents/slop/runs/elf-checkonly-2026-10-04.txt':
   'TOOLS.md:628 — the recorded stdout of `bend elf.bend --check-only` ("ALL PROOFS CHECK" / "done rc=0"). CONTENT IS A CAPTURED STREAM, NOT AN INSTRUMENT (kind() matched the substring `check` in `checkonly`).',
 '.agents/slop/state-mutate.py':
   'TOOLS.md:53 — one-token mutations of nn/state.bend; M12 = whitespace CONTROL.',
 '.agents/slop/substrate-audit.py':
   'TOOLS.md:1040 — "The OTHER root cause: 4 instruments that are right about a form and wrong about the substrate". Named by live formblind-census.py:439 SELF set.',
 '.agents/slop/tcptx-mutate.py':
   'TOOLS.md:55 — "51 one-edit mutations of renderer/tc_ptx.bend ... four whitespace CONTROLS and four move nothing for a real reason".',
 '.agents/slop/tools/mutate-dm.py':
   'TOOLS.md:42 — "applies one edit to uop/divandmod.bend ... RESTORES the file".',
 '.agents/slop/tools/mutate-sz.py':
   'TOOLS.md:45 — "one edit at a time to tinybendygrad/sz.bend ... does any output move?".',
 '.agents/slop/xd1/mutate.py':
   'TOOLS.md:526 — "the mutation tables: 13 and 10 one-edit reverts of this unit\'s own fixes"; TODO.md:3424 names it "Mutation driver".',
 'xd1/pin':
   'TOOLS.md:645 — "under the pin (`xd1/pin` = `6c3d401cf324`)". NAMES A PINNED REVISION / the checkout dir .agents/slop/xd1/pin, NOT A FILE. kind() matched the basename token `pin`.',
}
# corrections to the crude auto-state
FIX = {
 '.agents/slop/xd1/mutate.py': ('GONE',
   'no blob for this exact path in ANY ref (git log --all --diff-filter=A "*mutate.py" has no xd1/mutate.py; 75,336 history paths name no xd1/mutate.py); .agents/slop/xd1/ is .gitignore\'d and no mirror (dd-mirror, differverdict, .jjconflict-*) carries it. The only mutate.py files are a different generic runner.',
   '-'),
 'xd1/pin': ('NOT-A-PATH',
   'no file/dir of this path exists at repo root; it resolves to .agents/slop/xd1/pin (a checkout of the pinned bend revision). The revision it names, 6c3d401cf324, resolves to a commit in this repo. It is a revision reference, not a missing instrument.',
   'git cat-file -t 6c3d401cf324   # commit named by TOOLS.md:645'),
}

rows = []
for r in recs:
    p = r['path']
    if p in FIX:
        state, evid, restore = FIX[p]
    else:
        state, evid, restore = r['state'], r['evidence'], r['restore']
    rows.append([p, state, evid, restore, CLAIM.get(p, '')])

with open('.agents/slop/lostinst/INSTRUMENTS.tsv', 'w', newline='') as f:
    w = csv.writer(f, delimiter='\t', lineterminator='\n')
    w.writerow(['path', 'state', 'evidence', 'restore_or_generator', 'claim_carried'])
    w.writerows(rows)

from collections import Counter
c = Counter(r[1] for r in rows)
print('states:', dict(c), 'of', len(rows))
