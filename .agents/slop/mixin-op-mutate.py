#!/usr/bin/env python3
"""mixin-op-mutate.py -- the MEASURED mutation table for tinybendygrad/mixin/op.bend.

Each entry is a one-token edit. Each is applied, BOTH Bend lanes are run, the lanes are
required to agree, the rows are diffed against the unmutated output, and the edit is
reverted. A mutation that moves nothing is a measurement of what the gate does NOT see,
and it is reported rather than quietly dropped -- a table with no row that CANNOT move is
a table of coincidences.

    .venv/bin/python .agents/slop/mixin-op-mutate.py

BEND-ONLY rows count as moved: they are rows. The source is restored from a byte snapshot
on every exit path, including SIGINT/SIGTERM, and the run FAILS if it is left dirty.
"""
import os
import signal
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(ROOT, 'bin', 'bend')
SRC = os.path.join(ROOT, 'tinybendygrad', 'mixin', 'op.bend')
BIN = '/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/mop-mut.bin'

# (id, the search, the replace, what it is testing)
MUTATIONS = [
  ('M1', 'mo_alu2(T.Tensor.ar(r), T.Tensor.u(l), op, T.Tensor.u(r))',
         'mo_alu2(T.Tensor.ar(l), T.Tensor.u(r), op, T.Tensor.u(l))',
         '`src = (lhs, rhs)` (tensor.py:116). The SRC-ORDER row: two CONSTs print the same '
         'signature either way round, so `t_min0` is the pair with `t_min0i`.'),
  ('M2', 'mo_reshape.pick(F.eq_sints(mo_sints(ds), mo_dims(F.folded(T.Tensor.ar(t)), T.Tensor.u(t))), t, made)',
         'mo_reshape.pick(True{}, t, made)',
         '`mo_reshape`\'s identity test `ret.shape == self.shape` (movement.py:185), which is '
         'the only thing that decides whether a keepdim REDUCE grows a RESHAPE.'),
  ('M3', 'U32.from_nat(List.length(&2, O.Sint, t))', 'U32.from_nat(List.length(&2, O.Sint, ds))',
         '`mo_at`: the index of a head element is `len(t)`. An OFF-BY-ONE here is '
         'invisible to every signature row -- `RESHAPE(REDUCE, CONST(4))` and '
         '`RESHAPE(REDUCE, CONST(1))` print identically -- and only `sh_sum0kd` sees it.'),
  ('M4', 'case True{}: mo_arena(F.Folded.ar(fx), t)\n    case _: +f = E.ew_remint',
         'case _: mo_arena(F.Folded.ar(fx), t)\n    case True{}: +f = E.ew_remint',
         '`remint`\'s `same` arm (elementwise.py:30), and with it the whole promotion '
         'matrix on a weak CONST.'),
  ('M5', 'case False{} False{} : mo_cast_in(fx, t, od)', 'case False{} False{} : t',
         '`promote`\'s `cast` arm (elementwise.py:32) -- the arm every int CONST and every '
         'non-matching pair takes.'),
  ('M6', '    case True{}: mo_cast_t(t, W.wk_dt(F.folded(T.Tensor.ar(t)), T.Tensor.u(t)))\n    case _: t',
         '    case True{}: t\n    case _: mo_cast_t(t, W.wk_dt(F.folded(T.Tensor.ar(t)), T.Tensor.u(t)))',
         'reduce.py:45\'s trailing half/bfloat16/fp8 cast. A NEGATIVE for a float32 '
         'fixture -- the gate says so and cannot otherwise.'),
  ('M7', 'mo_n_minus(+cor: U32, +n: U32) -> U32: mo_n_minus.at(U32.is_lt(cor, n), cor, n)',
         'mo_n_minus(+cor: U32, +n: U32) -> U32: mo_n_minus.at(True{}, cor, n)',
         '`smax(n - correction, 0)` (helpers.py:65) and its saturating subtraction. With '
         '`correction=0` the two arms agree, so `t_var0c0` is the row that cannot move.'),
  ('M8', '  +mm = Softmax3.m(sx)\n  mo_sub(mm, mo_log(Softmax3.ss(sx)))',
         '  +mm = Softmax3.e(sx)\n  mo_sub(mm, mo_log(Softmax3.ss(sx)))',
         '`log_softmax` takes `_softmax`\'s `m` and NOT its `e` (op.py:706) -- the one line '
         'that distinguishes it from `softmax`. MEASURED UNFALSIFIABLE, and the reason is '
         'structural rather than a gap in the fixture: `ss = e.sum(...)` already pulls `e` '
         'into the graph, so `m - ss.log()` and `e - ss.log()` have the SAME node SET, the '
         'same count and the same op toposort, and differ only in two src INDEXES. The two '
         'programs are graph-isomorphic, so the CPython lane cannot separate them either -- '
         'tinygrad does not constant-fold. What DOES pin it is the `softmax3_m/e/ss` rows '
         '(8/11/13 nodes), which pin `_softmax`\'s three outputs; which of them '
         '`log_softmax` READS is verified against the Python source by reading it.'),
  ('M9', 'def mo_arena(+ar: O.Arena, +t: T.Tensor) -> T.Tensor: T.tn_new(ar, T.Tensor.u(t))',
         'def mo_arena(+ar: O.Arena, +t: T.Tensor) -> T.Tensor: t',
         'THE ARENA RULE (W9). Dropping it makes every "same dtype" answer carry a stale '
         'arena, and the failure is a `NOOP/0` rather than a wrong number.'),
  ('M10', '    case True{}  _       : mo_arena(F.Folded.ar(fx), t)',
          '    case True{}  _       : t',
          'The `is_invalid` arm (:29) must re-wrap in `fx`\'s arena too -- the same word '
          '("return `t`") as the weak-CONST arm and a different answer. `t_bin_promote` is '
          'the row, and it only sees this because `iv` is interned before `c`: with the '
          'operands the other way round both folds ARE the operand\'s own arena, the '
          're-wrap is a no-op, and this moves NOTHING. MEASURED, and the row was rebuilt.'),
  ('M11', '  mo_squeeze.pick(Bool.not(Bool.or(Nat.is_eq(mo_ndim(fx, T.Tensor.u(t)), 0n),\n'
          '    U32.is_eq(mo_dim_at(fx, T.Tensor.u(t), dim), 1))), t, dim)',
          '  mo_squeeze.pick(Bool.or(Nat.is_eq(mo_ndim(fx, T.Tensor.u(t)), 0n),\n'
          '    U32.is_eq(mo_dim_at(fx, T.Tensor.u(t), dim), 1)), t, dim)',
          'movement.py:308 -- `squeeze` RESHAPES a shape-(1,) source and the negation is '
          'the whole difference.'),
  ('M12', 'mo_mul(eq, mo_const_t(eq, O.CBool{True{}}))',
          'mo_mul(eq, mo_const_t(eq, mo_ki(1)))',
          'elementwise.py:613\'s `detect_positive` is a Python `bool`, so `ufix` makes a '
          'BOOL CONST and no promotion happens. An `int` here adds a CAST and two nodes.'),
  ('M13', '  +md = E.ew_detach(mo_max(True{}, t, axis))\n  +mm = mo_sub(t, md)',
          '  +md = mo_max(True{}, t, axis)\n  +mm = mo_sub(t, md)',
          '`_softmax`\'s `.detach()` (op.py:658). Both rows lose a node and the COUNT says so.'),
  ('M14', '  Softmax3{mm, ee, mo_sum(True{}, ee, axis)}', '  Softmax3{mm, mm, mo_sum(True{}, mm, axis)}',
          'THE TWO-RULES-ONE-NODE ROW. `_softmax` handing `m` back in its `e` slot drops '
          'the whole `CONST MUL EXP2` triple -- MEASURED, `softmax` prints 12 against 15 '
          'and `log_softmax` 15 against 18, and `softmax3_e` collapses onto `softmax3_m`.'),
  ('M15', 'mo_inverse(f, mo_max(kd, mo_inverse(f, t), axis))', 'mo_inverse(f, mo_inverse(f, t))',
          '`min`\'s INNER `_inverse` (op.py:494) together with the reduce. A `min` that is '
          'just `-x` prints two nodes and looks like a plausible answer.'),
  ('M16', 'def mo_iaxis(+axis: List<&2, U32>, i: U32) -> Bool: mo_iaxis.go(axis, i)',
          'def mo_iaxis(+axis: List<&2, U32>, i: U32) -> Bool: False{}',
          '`_reduce`\'s `1 if i in axis else s` (reduce.py:18). `sh_sum0kd` and the '
          'keepdim rows see it; `max0` and `sum0` do not, which is the point of the pair.'),
  ('M17', 'def mo_commit_dt(+fx: F.Folded, +t: T.Tensor) -> S.Dt:', 'def mo_commit_dt(+fx: F.Folded, +t: T.Tensor) -> S.Dt:  ',
          'a CONTROL -- a whitespace-only edit. A table with no row that CANNOT move is a '
          'table of coincidences.'),
]

_SNAP = b''


def restore(*_: object) -> None:
  with open(SRC, 'wb') as f:
    f.write(_SNAP)


def lanes() -> tuple[list[str], list[str]]:
  out = subprocess.run([BEND, SRC], capture_output=True, text=True, check=True).stdout
  subprocess.run([BEND, SRC, '-o', BIN], capture_output=True, check=True)
  nat = subprocess.run([BIN], capture_output=True, text=True, check=True).stdout
  return out.splitlines(), nat.splitlines()


def main() -> None:
  global _SNAP
  _SNAP = open(SRC, 'rb').read()
  for sig in (signal.SIGINT, signal.SIGTERM):
    signal.signal(sig, lambda s, _: (restore(), sys.exit(130)))
  try:
    base_int, base_nat = lanes()
    if base_int != base_nat:
      print('MUTATE: the two lanes DISAGREE on the unmutated file; stop')
      sys.exit(1)
    src = _SNAP.decode()
    for mid, find, repl, what in MUTATIONS:
      if src.count(find) != 1:
        print(f'{mid}: SKIPPED -- the search string is not unique ({src.count(find)})')
        continue
      with open(SRC, 'w') as f:
        f.write(src.replace(find, repl))
      try:
        mut_int, mut_nat = lanes()
      except subprocess.CalledProcessError as e:
        err = (e.stderr or b'').decode().strip().splitlines() or ['(no stderr)']
        print(f'{mid}: DOES NOT COMPILE -- {err[0]}')
        continue
      finally:
        restore()
      if mut_int != mut_nat:
        print(f'{mid}: the two lanes DISAGREE on the mutated file -- that is a bug, not a mutation')
      moved = [b.split('=', 1)[0] for a, b in zip(base_int, mut_int) if a != b]
      print(f'{mid}: {len(moved):2d} row(s) moved -- {" ".join(moved) if moved else "NOTHING MOVED"}')
      print(f'    {what}')
  finally:
    restore()
  dirty = open(SRC, 'rb').read() != _SNAP
  print('\nrestore check:', 'DIRTY' if dirty else 'clean')
  sys.exit(1 if dirty else 0)


if __name__ == '__main__':
  main()
