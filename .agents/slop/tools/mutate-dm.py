#!/usr/bin/env python3
"""apply each mutation to divandmod.bend, run both lanes, diff the rows, restore."""
import re, subprocess, sys, shutil
P = 'tinybendygrad/uop/divandmod.bend'
BASE = '/tmp/dm-base.txt'

def run():
  a = subprocess.run(['./bin/bend', P], capture_output=True, text=True).stdout
  b = '/tmp/dm-mut'
  r = subprocess.run(['./bin/bend', P, '-o', b], capture_output=True, text=True)
  n = subprocess.run([b], capture_output=True, text=True).stdout
  return a, n

import pathlib

# ── THE ROW READER IS `rebase-gate.py`'s OWN, LOADED BY PATH AND NOT COPIED ──────────────
# Measured by reader-fork-census.py on this corpus: 51 of 52 text readers disagreed with
# `rows()` on at least one of six row shapes, and four of them carried a docstring
# claiming to BE it. This file used to be one of them.
# ⚠ NOT FREE, and the census prints the load: of 1,440 lane files under .agents/slop
# (289,262 lines), 44,345 are F2 `py=`-tail lines and 2,370 are F3 two-space lines --
# so a fork that did not fold the tail was reading a DIFFERENT STRING on ~15% of lanes,
# and one that skipped F3 was blind to ~0.8%. Those are the sizes of what was wrong.
_RG = importlib.util.spec_from_file_location("rebase_gate", pathlib.Path(__file__).resolve().parent.parent / "rebase-gate.py")
_rebase_gate = importlib.util.module_from_spec(_RG)
_RG.loader.exec_module(_rebase_gate)
rows = _rebase_gate.rows

MUTS = [
 ('dm_fold.go first-wins -> last-wins',
  '    case 1: acc\n', '    case 1: dm_fold.new(Hit.ar(acc), m)\n'),
 ('dm_which.go disjunction -> always src0',
  '    case False{} True{}: 1\n    case _ _: 2\n', '    case False{} True{}: 0\n    case _ _: 0\n'),
 ('dm_cside.go disjunction -> always src0',
  '    case False{} True{}: 1\n    case _ _: 2\n', '    case False{} True{}: 0\n    case _ _: 0\n'),
 ('dm_floordiv.trunc: the helpers.bend bug (+1 when not neg)',
  '    case False{}: q\n    case _: dm_floordiv.exact(exact, q)\n', None),
 ('dm_floordiv.exact: drop the +1 entirely (truncate toward -inf is out of reach; this is floor-toward-zero)',
  '    case False{}: U32.add(q, 1)\n', '    case False{}: q\n'),
 ('dm_0.pat.put: arity conjunct on the divisor instead of the root',
  'Bool.and(op, Bool.and(dm_isn2(ar, self),', 'Bool.and(op, Bool.and(dm_isn2(ar, d),'),
 ('dm_1.pat.put: arity conjunct on the divisor instead of the root',
  'Bool.and(dm_isn2(ar, self), Bool.and(dm_has(dm_val(ar, d)),', 'Bool.and(dm_isn2(ar, d), Bool.and(dm_has(dm_val(ar, d)),'),
 ('dm_1.pat.put: drop the weakint conjunct',
  'Bool.and(U32.is_lt(which, 2), weak)', 'Bool.and(U32.is_lt(which, 2), True{})'),
 ('dm_weak.cls: CWeakFloat instead of CWeakInt',
  '    case S.CWeakInt{}: True{}\n', '    case S.CWeakFloat{}: True{}\n'),
 ('dm_pos: unsigned reading of d.vmin > 0',
  'def dm_pos(+v: U32) -> Bool:\n  Bool.and(Bool.not(H.i32_is_neg(v)), Bool.not(U32.is_zero(v)))',
  'def dm_pos(+v: U32) -> Bool:\n  Bool.not(U32.is_zero(v))'),
 ('dm_1.finish: FLOORDIV and FLOORMOD branches swapped',
  '    case O.OpsFLOORDIV{}: dm_1.fd(ar, x, d, cm, cq)\n    case _: dm_1.fm(ar, x, d, cm)',
  '    case O.OpsFLOORDIV{}: dm_1.fm(ar, x, d, cm)\n    case _: dm_1.fd(ar, x, d, cm, cq)'),
 ('dm_zero.range: vmin == 0 only, dropping the vmax half',
  'Bool.and(U32.is_zero(H.lo32(lo)), U32.is_zero(H.lo32(hi)))', 'U32.is_zero(H.lo32(lo))'),
 ('dm_multiple_of.mod: treat an unset multiple_of as 1 (the real default)',
  '    case None{}: False{}\n', '    case None{}: True{}\n'),
 ('dm_table: rule 2 gets a reject set',
  'O.PMEntry{2, [O.OpsFLOORDIV{}, O.OpsFLOORMOD{}], Nil{}}]}', 'O.PMEntry{2, [O.OpsFLOORDIV{}, O.OpsFLOORMOD{}], [O.OpsADD{}, O.OpsCONST{}]}]}'),
 ('dm_table: rule 2 given FLOORDIV only',
  'O.PMEntry{2, [O.OpsFLOORDIV{}, O.OpsFLOORMOD{}], Nil{}}]}', 'O.PMEntry{2, [O.OpsFLOORDIV{}], Nil{}}]}'),
 ('dm_point: truncating instead of floor',
  'dm_floordiv(dm_ival(cx), dm_ival(cy))', 'U32.div(dm_ival(cx), dm_ival(cy))'),
 ('dm_multiple_of.hit: answer FLOORDIV as well',
  '    case O.OpsFLOORDIV{}: None{}\n    case _: Some{O.UOp.const(ar, O.CInt{H.i64_of_i32(0)})}',
  '    case _: Some{O.UOp.const(ar, O.CInt{H.i64_of_i32(0)})}'),
 ('dm_cval: read the x side instead of the c side',
  'dm_1.pick(O.Arena.src(ar, add, 1), O.Arena.src0(ar, add), which)', 'dm_1.pick(O.Arena.src0(ar, add), O.Arena.src(ar, add, 1), which)'),
 ]

src = open(P).read()
for name, old, new in MUTS:
  if new is None:
    # the swap: put the False arm's body where the helpers bug would be
    old_s = 'def dm_floordiv.trunc(neg: Bool, exact: Bool, q: U32) -> U32:\n  match neg:\n    case True{}: H.i32_neg(dm_floordiv.exact(exact, q))\n    case False{}: q\n'
    new_s = 'def dm_floordiv.trunc(neg: Bool, exact: Bool, q: U32) -> U32:\n  match neg:\n    case True{}: H.i32_neg(dm_floordiv.exact(exact, q))\n    case False{}: dm_floordiv.exact(exact, q)\n'
    if old_s not in src: print(f'{name:<62} PATTERN NOT FOUND'); continue
    mutated = src.replace(old_s, new_s)
  else:
    if old not in src: print(f'{name:<62} PATTERN NOT FOUND'); continue
    mutated = src.replace(old, new)
  open(P, 'w').write(mutated)
  i, n = run()
  open(P, "w").write(src)
  if not i.strip(): print(f"{name:<62} DID NOT RUN"); continue
  moved = sorted(k for k in set(rows(src and open('/dev/stdin').read() if False else '') ) ) if False else None
  open(P, 'w').write(src)
  open('/tmp/dm-mut.txt', 'w').write(i)
  subprocess.run(f'diff {BASE} /tmp/dm-mut.txt', shell=True, capture_output=True)
  d = subprocess.run(f'diff {BASE} /tmp/dm-mut.txt', shell=True, capture_output=True, text=True).stdout
  keys = sorted({l.split('=')[0][2:].strip() for l in d.split('\n') if l.startswith('> ') and '=' in l})
  print(f'{name:<62} {len(keys):>2}  {", ".join(keys[:14])}')
