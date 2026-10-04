#!/usr/bin/env python3
"""THE MUTATION TABLE for the codegen3 split. Rows moved, BY NAME.

    python3 .agents/slop/codegen3-mut.py

Three questions, and the third matters most:

 1. DOES THE GATE STILL BITE FROM THE NEW FILES? A split that moved the code into
    three files could have blinded it -- if `rs_claimed` no longer reaches a row,
    nothing is wrong and the gate stays green. So four PORT mutations are run
    against the NEW files and must move the same rows the merged file's own
    mutation table records (N-a, M3, M7, and one that only coalesce can catch).
 2. DID THE SPLIT CHANGE ANY ANSWER? The thirteen renames are ALPHA-RENAMINGS, so
    by the Leibniz property they move nothing. That is a THEOREM and it is
    reported as one, not dressed up with a row that cannot fail.
 3. IS THE UNION ORDER LOAD-BEARING? The three files concatenate in PYTHON'S
    order. Swapping the order must make the byte-diff FAIL, because 54 rows with
    the right COUNT and the wrong ORDER is the trap that shipped a corrupted
    renderer once already.

A mutation is applied to ONE file, re-run (retried, because bend 2.0.34 machine-
stack-overflows about one run in twenty and prints ZERO rows, which is
indistinguishable from "not started"), and diffed as WHOLE `name=value` LINES
against the clean union. Every file is restored from a byte copy afterwards and the
restore is verified, so a mutation cannot leak into the tree.
"""
import os, shutil, subprocess, sys, tempfile
import patch_not_apply as PNA

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(ROOT, 'bin/bend')
FILES = ['tinybendygrad/codegen/simplify.bend',
         'tinybendygrad/codegen/late/coalesce.bend',
         'tinybendygrad/codegen/gpudims.bend']
SNAP  = os.path.join(ROOT, '.agents/slop/runs/base_codegen_rewriter.bend.txt')
BACK  = tempfile.mkdtemp()

def run(path):
    out = ''
    for _ in range(5):
        r = subprocess.run([BEND, path], capture_output=True, timeout=300)
        out = r.stdout.decode()
        if out.strip(): return out
    return out

def union(order=None):
    return ''.join(run(os.path.join(ROOT, f)) for f in (order or FILES))

def rows(t): return [l for l in t.split('\n') if '=' in l]

def moved(base, mut):
    b, m = rows(base), rows(mut)
    bd = dict(l.split('=', 1) for l in b); md = dict(l.split('=', 1) for l in m)
    out = [k for k in sorted(set(bd) | set(md)) if bd.get(k, '<ABSENT>') != md.get(k, '<ABSENT>')]
    if len(b) != len(m): out.append('(ROW COUNT %d -> %d)' % (len(b), len(m)))
    return out

MUTATIONS = [
 ('X1  `rs_claimed` claims GLOBAL only  (N-a, replayed from the NEW file)',
  'tinybendygrad/codegen/gpudims.bend',
  [('  Bool.or(O.eq_axis(at, O.AXIS_GLOBAL{}), O.eq_axis(at, O.AXIS_LOCAL{}))',
    '  Bool.or(O.eq_axis(at, O.AXIS_GLOBAL{}), Bool.and(False{}, False{}))')]),
 ('X2  `fr_off` also claims LINEAR  (M3, replayed from the NEW file)',
  'tinybendygrad/codegen/simplify.bend',
  [('            RW.rw_is(ar, i, O.OpsREDUCE{}), RW.rw_is(ar, i, O.OpsCALL{}))',
    '            RW.rw_is(ar, i, O.OpsREDUCE{}),\n            Bool.or(RW.rw_is(ar, i, O.OpsCALL{}), RW.rw_is(ar, i, O.OpsLINEAR{})))')]),
 ('X3  `symbolic_len` 123 -> 122  (M7, replayed from the NEW file)',
  'tinybendygrad/codegen/simplify.bend',
  [('def symbolic_len() -> U32:\n  123', 'def symbolic_len() -> U32:\n  122')]),
 ('X4  `indexing_simplify` loses its second rule  (only coalesce can catch this)',
  'tinybendygrad/codegen/late/coalesce.bend',
  [('  [O.PMEntry{0, [O.OpsINDEX{}], [O.OpsWHERE{}]},       # coalesce.py:62 INDEX(buf, invalid_gate)\n'
    '   O.PMEntry{1, [O.OpsINDEX{}], [O.OpsWHERE{}]}]', '  [O.PMEntry{0, [O.OpsINDEX{}], [O.OpsWHERE{}]}]')]),
 ('X5  rename reverted: `pm_simplify_ranges` -> `sr_table`   (THEOREM: alpha)',
  'tinybendygrad/codegen/simplify.bend', [('pm_simplify_ranges()', 'sr_table()')]),
 ('X6  the rename SWAP reverted: rule/table back to `pm_flatten_range`/`fr_table`  (THEOREM)',
  'tinybendygrad/codegen/simplify.bend',
  [('def pm_flatten_range() -> List<&2, O.PMEntry>:', 'def fr_table() -> List<&2, O.PMEntry>:'),
   ('def flatten_range(+ar: O.Arena, self: U32) -> RW.Rew:\n  fr_scan(pm_flatten_range()',
    'def pm_flatten_range(+ar: O.Arena, self: U32) -> RW.Rew:\n  fr_scan(fr_table()'),
   ('  RW.n_of(pm_flatten_range())', '  RW.n_of(fr_table())'),
   ('  flatten_range(F.Folded.ar(RW.G.fx(gx)), RW.G.at(gx, n))',
    '  pm_flatten_range(F.Folded.ar(RW.G.fx(gx)), RW.G.at(gx, n))')]),
]

if __name__ == '__main__':
    for f in FILES: shutil.copy(os.path.join(ROOT, f), os.path.join(BACK, os.path.basename(f)))
    snap = open(SNAP).read()
    clean = union()
    print('CLEAN UNION: %d rows;  snapshot: %d rows;  %s'
          % (len(rows(clean)), len(rows(snap)), 'BYTE-IDENTICAL' if clean == snap else 'DIFFERS'))
    for label, path, reps in MUTATIONS:
        p = os.path.join(ROOT, path); t = open(p).read()
        for old, new in reps:
            if old not in t:
                PNA.fail("anchor not found in %s: %r" % (path, old[:60]))
            t = t.replace(old, new)
        open(p, 'w').write(t)
        mut = union()
        chk = subprocess.run([BEND, p, '--check-only'], capture_output=True).stdout.decode().split('\n')[0]
        for f in FILES: shutil.copy(os.path.join(BACK, os.path.basename(f)), os.path.join(ROOT, f))
        m = moved(clean, mut)
        print('\n%-70s moved: %s' % (label, ', '.join(m) if m else 'NOTHING'))
        print('%70s   check-only first line: %s' % ('', chk))
    print('\nrestored: %s' % ('all four files byte-identical to the backup' if all(
        open(os.path.join(ROOT, f)).read() == open(os.path.join(BACK, os.path.basename(f))).read()
        for f in FILES) else 'RESTORE FAILED -- DO NOT TRUST THIS RUN'))
    print('clean again: %s' % ('BYTE-IDENTICAL to the snapshot' if union() == snap else 'DIFFERS'))
    for order, label in ((FILES, "python order (simplify, coalesce, gpudims)"),
                         ([FILES[2], FILES[1], FILES[0]], 'reversed')):
        print('union order %-40s %s the snapshot' % (label,
              'MATCHES' if union(order) == snap else 'DIFFERS FROM'))
    shutil.rmtree(BACK)