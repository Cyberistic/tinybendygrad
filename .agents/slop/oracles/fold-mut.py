#!/usr/bin/env python
# fold-mut.py -- the mutation harness for the MOVEMENT rows of tinybendygrad/uop/fold.bend.
#
# Each mutation is a ONE-TOKEN edit to the source, the file is re-run in BOTH lanes,
# and the rows that CHANGED are reported. A mutation that moves nothing is a BLIND
# SPOT in the gate and is reported as one, never closed with a row that encodes the
# bug.
#
#     .venv/bin/python .agents/slop/oracles/fold-mut.py
import subprocess, sys, os, tempfile

ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
SRC = os.path.join(ROOT, "tinybendygrad/uop/fold.bend")
BEND = os.path.join(ROOT, "bin/bend")

MUTATIONS = [
  # (id, what it breaks, old, new)
  ("M1", "EXPAND: marg and ps SWAPPED (`both(a,b)` -> `both(b,a)`) -- the shape is wrong and the count is not",
   "dt_of(src_dt(0, ss), both(marg(ar, i), src_shape(0, ss)))",
   "dt_of(src_dt(0, ss), both(src_shape(0, ss), marg(ar, i)))"),

  ("M2", "PAD: the sum is SHRINK's `o+sz<=s` instead of PAD's `o+s<=sz` -- the two arms swapped",
   "Bool.pick(Bool, pad, U32.is_le(U32.add(o, s), z), U32.is_le(U32.add(o, z), s))",
   "Bool.pick(Bool, pad, U32.is_le(U32.add(o, z), s), U32.is_le(U32.add(o, s), z))"),

  ("M3", "PAD/SHRINK: the length check DROPPED (`_ _ _` -> `x`) -- a marg of the wrong length now answers",
   "    case _ _ _                      : Pairs{Pairs.szs(x), False{}}",
   "    case _ _ _                      : x"),

  ("M4", "PERMUTE: the no-repeat half DROPPED -- only the range test remains",
   "      Bool.and(Perm.ok(x), Bool.not(mem_u32(Perm.seen(x), y)))}",
   "      Perm.ok(x)}"),

  ("M5", "PERMUTE: `ps` is seeded EMPTY instead of the shape -- the walk cannot read a dim",
   "def perm_init(ys: List<&2, U32>, +ps: List<&2, O.Sint>) -> Perm:\n  perm.go(ys, ps, Perm{Nil{}, Nil{}, True{}})",
   "def perm_init(ys: List<&2, U32>, +ps: List<&2, O.Sint>) -> Perm:\n  perm.go(ys, Nil{}, Perm{Nil{}, Nil{}, True{}})"),

  ("M6", "FLIP: the length check DROPPED -- any arg length answers",
   "dt_of_if(Nat.is_eq(List.length(&2, U32, ys), List.length(&2, O.Sint, ps)), src_dt(0, ss), Some{ps})",
   "dt_of_if(True{}, src_dt(0, ss), Some{ps})"),

  ("M7", "PERMUTE: the picked dim is APPENDED AT THE FRONT instead of the back -- a reverse the count cannot see",
   "    case Some{v}: Perm{List.append(&2, O.Sint, Perm.ds(x), [v]),",
   "    case Some{v}: Perm{List.append(&2, O.Sint, [v], Perm.ds(x)),"),

  ("M8", "the DTYPE arm reads `void` instead of `src[0].dtype` -- a movement's dtype is silently always-void",
   "def pair_ds.put(+pad: Bool, x: Maybe<&1, Pairs>, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:\n  match x:\n    case Some{+v}: dt_of_if(Pairs.ok(v), src_dt(0, ss), Some{Pairs.szs(v)})",
   "def pair_ds.put(+pad: Bool, x: Maybe<&1, Pairs>, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:\n  match x:\n    case Some{+v}: dt_of_if(Pairs.ok(v), S.void(), Some{Pairs.szs(v)})"),

  # M9 and M10 are MEASURED EQUIVALENCES, not gate gaps -- see the report. M9's `SU`
  # arm is unreachable (no shape reader in the tree mints an `O.SU`), and M10 is PAD's
  # own `o+s<=sz`, which is SYMMETRIC in o and s, so swapping `ps` with the offsets
  # cannot change any answer or any length check. They are run anyway and reported.
  ("M9", "a symbolic dim is treated as 0 instead of refused (`count_of`'s SU arm) -- UNREACHABLE STATE",
   "    case O.SU{u}: None{}\n    case O.SI{i}: count_of.of(i)",
   "    case O.SU{u}: Some{0}\n    case O.SI{i}: count_of.of(i)"),

  ("M10", "PAD reads src[1] as `ps` -- SOURCE and OFFSETS swapped. AN EQUIVALENCE: `o+s<=sz` is symmetric",
   "  pair_ds.of(True{}, pair3.of(True{}, src_shape(0, ss), marg.at(1, ar, i), marg.at(2, ar, i)), ss)",
   "  pair_ds.of(True{}, pair3.of(True{}, marg.at(1, ar, i), src_shape(0, ss), marg.at(2, ar, i)), ss)"),
  ("M10b", "...and the same swap in the SHRINK arm, which is where it is NOT an equivalence",
   "  pair_ds.of(False{}, pair3.of(False{}, src_shape(0, ss), marg.at(1, ar, i), marg.at(2, ar, i)), ss)",
   "  pair_ds.of(False{}, pair3.of(False{}, marg.at(1, ar, i), src_shape(0, ss), marg.at(2, ar, i)), ss)"),

  ("M11", "PAD/SHRINK read src[2] as `ps` -- the source and the SIZES swapped (the classic shape-arg swap)",
   "  pair_ds.of(True{}, pair3.of(True{}, src_shape(0, ss), marg.at(1, ar, i), marg.at(2, ar, i)), ss)",
   "  pair_ds.of(True{}, pair3.of(True{}, src_shape(0, ss), marg.at(2, ar, i), marg.at(1, ar, i)), ss)"),

  ("M12", "PERMUTE reads its arg from src[0] instead of `self.arg` -- `marg` is the wrong half",
   "def order_arg(arg: O.Arg) -> List<&2, U32>:\n  match arg:\n    case O.ATuple{ys}: ys\n    case _           : Nil{}",
   "def order_arg(arg: O.Arg) -> List<&2, U32>:\n  Nil{}\n\ndef order_arg_unused(arg: O.Arg) -> List<&2, U32>:\n  match arg:\n    case O.ATuple{ys}: ys\n    case _           : Nil{}"),

  ("M13", "EXPAND/PAD/SHRINK/PERMUTE/FLIP ALL return `void` -- the dtype arm of the whole group",
   "def expand_ds(+ar: O.Arena, i: U32, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:\n  dt_of(src_dt(0, ss), both(marg(ar, i), src_shape(0, ss)))",
   "def expand_ds(+ar: O.Arena, i: U32, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:\n  dt_of(S.void(), both(marg(ar, i), src_shape(0, ss)))"),
]


def run(path, native=False):
  if native:
    out = tempfile.mktemp(suffix="")
    r = subprocess.run([BEND, path, "-o", out], capture_output=True, text=True, cwd=ROOT)
    if r.returncode != 0:
      return None
    r2 = subprocess.run([out], capture_output=True, text=True)
    os.unlink(out)
    return r2.stdout
  r = subprocess.run([BEND, path], capture_output=True, text=True, cwd=ROOT)
  return r.stdout if r.returncode == 0 else None


base = open(SRC).read()
b_int = run(SRC)
b_nat = run(SRC, native=True)
assert b_int is not None and b_nat is not None, "baseline does not run"
assert b_int == b_nat, "baseline lanes differ"
def rows_of(out):
  # a row is `name` or `name rest`; the `True` rows have no space, so they key alone
  r = {}
  for l in out.strip().split("\n"):
    k, _, v = l.partition(" ")
    r[k] = v or "True"
  return r

b_rows = rows_of(b_int)
print(f"baseline: {len(b_rows)} rows, both lanes identical")
print()

for mid, what, old, new in MUTATIONS:
  if old not in base:
    print(f"{mid}: NOT APPLIED -- the anchor text is not in the file")
    continue
  mutated = base.replace(old, new, 1)
  p = SRC + ".mut"
  open(p, "w").write(mutated)
  try:
    o_int = run(p)
    o_nat = run(p, native=True)
    if o_int is None or o_nat is None:
      lane = "interp-FAILED" if o_int is None else "native-FAILED"
      o = o_int if o_int is not None else o_nat
      if o is None:
        print(f"{mid}: CHECK FAILS in both lanes -- {what}")
        continue
      o_int = o
      lanes = lane
    else:
      lanes = "both" if o_int == o_nat else "LANES DIFFER"
    m_rows = rows_of(o_int)
    moved = [k for k in b_rows if k not in m_rows or m_rows[k] != b_rows[k]]
    print(f"{mid} [{lanes}]: {len(moved)} row(s) moved -- {what}")
    for k in sorted(moved):
      bv, mv = b_rows.get(k, "<gone>"), m_rows.get(k, "<gone>")
      bv = bv[:70] + ("..." if len(bv) > 70 else "")
      mv = mv[:70] + ("..." if len(mv) > 70 else "")
      print(f"    {k}: {bv}  ->  {mv}")
    if not moved:
      print("    *** BLIND SPOT: this mutation moves NOTHING ***")
    print()
  finally:
    os.unlink(p)
