#!/usr/bin/env python3
"""Mutate `tinybendygrad/nn/__init__.bend` one token at a time and report which
gate rows MOVE. From the repo root:

    .venv/bin/python .agents/slop/nn-init-mutate.py

The mutated copy MUST live in `tinybendygrad/nn/` beside the original: the
imports are RELATIVE, so a copy in /tmp cannot resolve them and every mutation
would report "did not compile" for a reason that has nothing to do with the
mutation. MEASURED, and it is why this writes into the tree and puts the
original back.
"""
import subprocess, os, shutil
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(ROOT, 'bin', 'bend')
F = os.path.join(ROOT, 'tinybendygrad', 'nn', '__init__.bend')

MUT = [
  # --- the padding='same' comprehension at :102 ---
  ('M1  the half-pad ignores the dilation',
   'nn_pair.right(nn_prod(d, k), nn_half(nn_prod(d, k)))',
   'nn_pair.right(nn_prod(d, k), nn_half(nn_prod(1, k)))'),
  # --- the REVERSAL in :102, and the only row family that can see it ---
  ('M2  the two lists are walked forwards, not reversed',
   'H.flatten_u32(nn_pad.go(List.reverse(&2, U32, nn_mt(dil, nn_len(ks))),\n    List.reverse(&2, U32, ks), Nil{}))',
   'H.flatten_u32(nn_pad.go(nn_mt(dil, nn_len(ks)), ks, Nil{}))'),
  # --- `//` vs `/` in the half-pad ---
  ('M3  the half-pad is `m` and not `m//2`',
   'nn_pair.right(+m: U32, +h: U32) -> List<&2, U32>:\n  [h, U32.sub(m, h)]',
   'nn_pair.right(+m: U32, +h: U32) -> List<&2, U32>:\n  [h, m]'),
  # --- BatchNorm's `__dict__` ORDER at :33-39 ---
  ('M4  num_batches_tracked is put LAST, not third',
   'bn_st.trk(track, nn_app(bn_st.aff(affine, w, b), ST.Ent{"num_batches_tracked", T.tn_is_param_(nbt, False{})}), rm, rv)',
   'bn_st.trk(track, bn_st.aff(affine, w, b), rm, rv)'),
  # --- the `is_param_(False)` at :38, which `Optimizer` (:13) filters on ---
  ('M5  num_batches_tracked is a parameter',
   'ST.Ent{"num_batches_tracked", T.tn_is_param_(nbt, False{})}',
   'ST.Ent{"num_batches_tracked", nbt}'),
  # --- the `track_running_stats` ternary at :39 ---
  ('M6  the running stats are always added',
   'Bool.pick(List<&2, ST.Ent>, track,\n    nn_app(nn_app(acc, ST.Ent{"running_mean", T.tn_is_param_(rm, False{})}),\n      ST.Ent{"running_var", T.tn_is_param_(rv, False{})}),\n    acc)',
   'nn_app(nn_app(acc, ST.Ent{"running_mean", T.tn_is_param_(rm, False{})}),\n      ST.Ent{"running_var", T.tn_is_param_(rv, False{})})'),
  # --- `shape_mask` -- the two head elements at :42 ---
  ('M7  the mask has no `-1`',
   'bn_mask.go(nn_sat2(U32.to_nat(ndim)), [H.i64_of_i32(1), nn_neg1()])',
   'bn_mask.go(nn_sat2(U32.to_nat(ndim)), [H.i64_of_i32(1)])'),
  # --- the saturating tail count at :42 ---
  # The FIRST attempt at this mutation dropped the `Succ{0n}` arm and kept
  # `case _: 0n`, which is SEMANTICALLY IDENTICAL -- `0n` and `1n` both reach the
  # same answer either way -- so it moved NOTHING for a reason that had nothing to
  # do with the gate. That is recorded here rather than quietly dropped, because
  # "a mutation that cannot move" and "a mutation that does not change the
  # function" look identical in a table and are not the same thing.
  ('M8  the `[1]*(ndim-2)` tail does not saturate',
   'def nn_sat2(n: Nat) -> Nat:\n  match n:\n    case 0n: 0n\n    case Succ{0n}: 0n\n    case Succ{Succ{p}}: p',
   'def nn_sat2(n: Nat) -> Nat:\n  match n:\n    case 0n: 0n\n    case Succ{p}: p'),
  ('M8b the same, dropping the zero case as well',
   'def nn_sat2(n: Nat) -> Nat:\n  match n:\n    case 0n: 0n\n    case Succ{0n}: 0n\n    case Succ{Succ{p}}: p',
   'def nn_sat2(n: Nat) -> Nat: n'),
  # --- `reduce_axes` -- the `!= 1` filter at :47 ---
  ('M9  reduce_axes excludes axis 0 instead of axis 1',
   'Bool.pick(List<&2, U32>, U32.is_eq(i, 1),\n        acc, List.append(&2, U32, acc, [i])))',
   'Bool.pick(List<&2, U32>, U32.is_eq(i, 0),\n        acc, List.append(&2, U32, acc, [i])))'),
  # --- ConvTranspose2d's TRANSPOSED weight at :150 ---
  ('M10 ConvTranspose2d reuses Conv2d\'s weight shape',
   'List.append(&2, U32, [in_c, nn_groups(out_c, groups)], ks)',
   'List.append(&2, U32, [out_c, nn_groups(in_c, groups)], ks)'),
  # --- the `in_channels//groups` at :106 is NOT guarded and must not be ---
  ('M11 the group division is guarded against 0',
   'def nn_groups(in_c: U32, groups: U32) -> U32: U32.div(in_c, groups)',
   'def nn_groups(in_c: U32, groups: U32) -> U32: U32.max(1, U32.div(in_c, groups))'),
  # --- LayerNorm's `-1-i` axis at :253 ---
  ('M12 the axis counts up instead of down',
   'nn_i64_app(acc, H.i64_of_hi_lo(4294967295, U32.sub(4294967295, m))))',
   'nn_i64_app(acc, H.i64_of_hi_lo(4294967295, m)))'),
  # --- RMSNorm's `-1` axis at :300, resolved against the rank ---
  ('M13 the RMSNorm axis is 0 rather than ndim-1',
   '[U32.sub(ndim, 1)]', '[0]'),
  # --- a control ---
  ('M14 a no-op edit', 'nn_row("nn_lin"', 'nn_row("nn_lin"  '),
]

def rows(src):
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
base, _ = rows(base_src)
print('baseline rows: %d' % len(base))
print('baseline RED: %s' % ([k for k, v in base.items() if v != 'True'] or 'none'))
print()
print('| mutation | rows that MOVED | note |')
print('| --- | --- | --- |')
for name, old, new in MUT:
  n = base_src.count(old)
  if n != 1:
    print('| %s | SKIPPED (pattern occurs %d times) | |' % (name, n))
    continue
  got, allout = rows(base_src.replace(old, new))
  if not got:
    msg = [l for l in allout.strip().splitlines() if l.strip()][:2]
    print('| %s | DID NOT COMPILE | %s |' % (name, ' / '.join(msg)[:70]))
    continue
  moved = [k for k in base if got.get(k) != base[k]]
  print('| %s | %s | %s |' % (name, ', '.join(moved) or '**NOTHING**',
    'a NEGATIVE: nothing can see this' if not moved else
    'now red: ' + ','.join(k for k in moved if got[k] != 'True')))
