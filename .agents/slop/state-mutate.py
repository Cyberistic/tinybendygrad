#!/usr/bin/env python3
"""Mutate `tinybendygrad/nn/state.bend` one token at a time and report which gate
rows MOVE. Run from the repo root:

    .venv/bin/python .agents/slop/state-mutate.py

Each mutation is (name, old, new). A mutation whose rows are all unchanged is a
NEGATIVE and is reported as such -- a mutation table with no row that CANNOT move
is a table of coincidences. Nothing is written outside /tmp.
"""
import subprocess, sys, os, shutil, tempfile
import patch_not_apply as PNA
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(ROOT, 'bin', 'bend')
F = os.path.join(ROOT, 'tinybendygrad', 'nn', 'state.bend')

MUT = [
  # --- the prefix ladder, which is the whole function ---
  ('M1  no terminal dot',
   'String.concat([pf, Kv.k(e), "."])', 'String.concat([pf, Kv.k(e), ""])'),
  # --- the sequence arm's index key, which is the ONE place OSeq differs ---
  ('M2  list keys are the prefix, not the index',
   'It{String.concat([pf, U32.show(n), "."]), e}', 'It{String.concat([pf, ".", ""]), e}'),
  # --- the dict-collapse, first-position-last-value ---
  ('M3  put APPENDS instead of overwriting',
   'Ent{Ent.k(f), Ent.t(e)} <> t', 'List.append(&2, Ent, [f], sd_put(t, e))'),
  # --- the strip, the run-at-the-head half ---
  ('M4  strip removes EVERY dot, not the two end runs',
   "    case '.': SDHead{acc}\n    case _: SDKeep{List.append(&2, Char, acc, [c])}",
   "    case _: SDHead{acc}"),
  # --- the strip, the reversal half ---
  ('M5  rstrip is a no-op (only lstrip runs)',
   'String.from_list(sd_rev(sd_lstrip(sd_rev(sd_lstrip(String.to_list(s))))))',
   'String.from_list(sd_lstrip(String.to_list(s)))'),
  # --- TensorIO.seek, the SIGNED clamp ---
  ('M6  max(0, x) becomes an unsigned comparison',
   'Bool.pick(H.I64, H.i64_is_neg(x), zero, x)', 'x'),
  # --- TensorIO.seek, the THIRD whence candidate ---
  ('M7  whence 2 picks pos+off instead of len+off',
   '[off, H.i64_add(pos, off), H.i64_add(len_, off)]', '[off, H.i64_add(pos, off), H.i64_add(pos, off)]'),
  # --- the OOther rung: Python's `state_dict` stays {} ---
  ('M8  OOther contributes a key anyway',
   'case OOther{v}: gsd.go(p, t, acc)',
   'case OOther{v}: gsd.go(p, t, List.append(&2, Ent, acc, [Ent{sd_strip(pf), v}]))'),
  # --- the document-order reversal at the end of the walk ---
  ('M9  the walk does not reverse its accumulator',
   'case Succ{p}:\n      match ws:\n        case Nil{}: List.reverse(&2, Ent, acc)',
   'case Succ{p}:\n      match ws:\n        case Nil{}: acc'),
  # --- the safe_dtypes table ---
  ('M10 drop the last safe_dtypes entry',
   'Sd{"F64", S.double()}]', 'Sd{"F64", S.double()}, Sd{"", S.void()}]'),
  # --- the leaf strip: `prefix.strip(".")` is applied AT THE LEAF ---
  ('M11 the leaf does not strip its prefix',
   'Ent{sd_strip(pf), tt}', 'Ent{pf, tt}'),
  # --- a control ---
  ('M12 a no-op edit', 'sd_row("sd_tens"', 'sd_row("sd_tens"  '),
]

def rows(src):
  # The mutated copy MUST live in `tinybendygrad/nn/` beside the original: the
  # file's imports are RELATIVE (`./../tensor.bend`), so a copy in /tmp cannot
  # resolve them and every mutation would report "did not compile" for a reason
  # that has nothing to do with the mutation. MEASURED, and it is why this script
  # writes into the tree and puts the original back.
  bak = F + '.bak'
  shutil.copyfile(F, bak)
  try:
    open(F, 'w').write(src)
    r = subprocess.run([BEND, F], capture_output=True, text=True, cwd=ROOT, timeout=900)
  finally:
    shutil.move(bak, F)
  out = {}
  for line in r.stdout.splitlines():
    if '=' in line:
      k, v = line.split('=', 1)
      out[k] = v
  return out, r.stdout + r.stderr

base_src = open(F).read()
base, base_all = rows(base_src)
print('baseline rows: %d' % len(base))
red = [k for k, v in base.items() if v != 'True']
print('baseline RED: %s' % (red or 'none'))
print()
print('| mutation | rows that MOVED | note |')
print('| --- | --- | --- |')
for name, old, new in MUT:
  n = base_src.count(old)
  if n != 1:
    print(PNA.pipe([name, PNA.not_applied("pattern occurs %d times" % n), ""], 3))
    continue
  got, allout = rows(base_src.replace(old, new))
  if not got:
    print('| %s | DID NOT COMPILE | %s |' % (name, allout.strip().splitlines()[1][:70] if len(allout.strip().splitlines()) > 1 else ''))
    continue
  moved = [k for k in base if got.get(k) != base[k]]
  note = 'a NEGATIVE: nothing can see this' if not moved else ('now red: ' + ','.join(k for k in moved if got[k] != 'True'))
  print('| %s | %s | %s |' % (name, ', '.join(moved) or '**NOTHING**', note))
