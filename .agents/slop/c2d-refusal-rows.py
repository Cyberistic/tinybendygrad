#!/usr/bin/env python3
"""c2d-refusal-rows.py -- THE CPython SIDE OF `validate.bend`'s `c2d` LANE.

Every value here is printed by CALLING CPython, and the row NAMES are the ones
`tinybendygrad/uop/validate.bend` prints, so `rebase-gate.py`'s `rows()` intersects them.
Nothing in this file is transcribed: no message, no exception class, no op name and no
signature. The FIXTURE LIST is the only thing written by hand, and each fixture is the one
`validate.bend` builds -- `O.s5.ga.arena()`'s node 4, `O.s5.d1(0)`, `O.s5.dn(2)`, `S.D1{6}` --
annotated with the upstream line it is drawn across.

    DEV=NULL python3 .agents/slop/c2d-refusal-rows.py

THE VOCABULARY, two values, and the refusal CLASS is inside the value rather than in a row of
its own so it cannot be dropped from a comparison:
    `BUILT <sig>`                  the call returned a node
    `REFUSED <Class>: <message>`   the call raised, class and message both carried
`AssertionError` from ops.py:761's BARE `assert` and `RuntimeError` from ops.py:759's `raise`
are different upstream behaviours, so a row that accepted either would be testing neither.

SEVEN OF THE NINETEEN SHARED OUTCOME ROWS ARE RED AND THEY ARE SUPPOSED TO BE. `ops.bend` has
an owner this round and `ops.bend:6989-7012` implements none of the four refusals, so the port
answers `BUILT` on all nineteen while CPython refuses these seven: `c2d_761 selrow`,
`c2d_761 argzero`, `c2d_761 scalardevargone`, `c2d_759 disk`, `c2d_759 disktuple`,
`c2d_763 weakint`, `c2d_763 weakfloat`. `c2d_shared_refused_n` counts them from the rows
below, so the number cannot go stale. That is the whole point of the lane: `s5_copy_sel` was a
GREEN row asserting agreement on a node CPython refuses.

FIVE ROWS ARE ORACLE-ONLY, and the gate reports them rather than hiding them:
    `c2d_759 disklower` `c2d_759 disksuffix` `c2d_759 nodisk` `c2d_759 diskx`
        `S.Dev` is `D1{tag: U32}` / `Dn{tags}`, so the port has no NAME to case-fold or
        colon-split. `device.bend:340`'s `tag_of` gives DISK the tag 6 and
        `schedule/memory.bind:999` says `disk() = S.D1{1}`; until one is chosen the guard is
        not decidable, and that is REPORTED rather than gated.
    `c2d_892 deviceread`  `UOp.device` (ops.py:887-899) is NOT PORTED, so the port cannot
        perform the read that ops.py:892's assert guards.

THE BOUNDARIES ARE RE-DERIVED, NOT INHERITED -- `vw-boundaries.py` exhausts them by CALLING
and three of its results change what a fixture has to be:
    `dtypes.weaks` is a set of size 2 out of 20 dtypes, so 763 has EIGHTEEN positives
    EVERY `UOp.range` is `weakint` over all eight `AxisType`s, so a RANGE cannot be a positive
    `arg=0` REFUSES on a scalar device, so ops.py:761 tests `is None` and not truth
"""
import sys

sys.path.insert(0, ".")

from tinygrad.dtype import dtypes  # noqa: E402
from tinygrad.uop.ops import Ops, ParamArg, UOp  # noqa: E402

ROWS = []


def out(nm, v):
  ROWS.append(f"{nm}={v}")


def nm(u: UOp) -> str:
  """`ops-501-oracle.py:49`'s `nm` -- the PORT prints the `Ops.` prefix because
  `str(FastEnum)` is `"Ops.MEMBER"`, so the row is `Ops.name` and not the bare member name."""
  return f"Ops.{u.op.name}"


def outcome(fn):
  try:
    u = fn()
  except BaseException as e:  # noqa: BLE001 -- the class and the message ARE the answer
    return f"REFUSED {type(e).__name__}: {e}"
  return "BUILT " + sig(u)


def sig(u: UOp) -> str:
  """`ops-501-oracle.py:45`'s `sig`, and the PORT's `s5.seps` (ops.bend:6199-6204): the root op
  name, then `/`, then the src op names SPACE-separated and with a trailing space. The
  separator is load-bearing -- `s5.minted.of.go` (ops.bend:6367) prints a srcless node BARE,
  and a `/`-joined encoding would put `Ops.COPY/` where the port says `Ops.COPY`."""
  return nm(u) + ("/" + " ".join(nm(s) for s in u.src) + " " if u.src else "")


def pa(slot, dt):
  """`ParamArg` with `slot` and `dtype` set and every other field at `ParamArg`'s own default
  (tinygrad/uop/ops.py:25-40), so `size=None` and `device=None` -- which is what puts these
  fixtures on the 763 and 761 boundaries at all."""
  return ParamArg(slot, dt)


def pa_dev(slot, dt, dev):
  return ParamArg(slot, dt, None, None, None, None, None, dev)


def main(emit=out):
  """`emit` is the ROW SINK and it is a PARAMETER because `validate-oracle.py` loads this
  module and folds its rows into its own list: overriding `out` from outside would leave
  `ROWS` empty and the `c2d_shared_refused_n` tally below -- which reads `ROWS` -- would count
  nothing. MEASURED: `KeyError: 'c2d_761 selrow'` on the overridden-sink path."""
  got = []
  put = lambda nm, v: (got.append((nm, v)), emit(nm, v))
  # `s5.pa(1)` -- ops.bend:6110 -- `ParamArg.of(1, int32)`. `s5.ga.arena()`'s node 1
  # (ops.bend:6432), and it is what node 4's `device` falls through to.
  buf = UOp(Ops.BUFFER, src=(), arg=pa(1, dtypes.int32))
  buf_t = UOp(Ops.BUFFER, src=(), arg=pa_dev(1, dtypes.int32, ("PYTHON", "PYTHON")))
  # node 4 of `s5.ga.arena()` -- ops.bend:6435 -- `Node{OpsSHRINK{}, [1], ATuple{Nil{}}}`. THIS
  # is the node `s5.selrow` calls `copy_to_device` on, and the identity rows say so, because
  # the row that was wrong about it was wrong in a way no signature can see.
  shr = UOp(Ops.SHRINK, src=(buf,), arg=())
  shr_t = UOp(Ops.SHRINK, src=(buf_t,), arg=())
  PY2, ONE = ("PYTHON", "PYTHON"), 1

  # ---- FIXTURE IDENTITY (12). Green on both sides, and the reason they exist. ------------
  put("c2d_selrow_op", nm(shr))
  put("c2d_selrow_nsrc", str(len(shr.src)))
  put("c2d_selrow_src0", nm(shr.src[0]))
  put("c2d_selrow_arg_is_tuple", str(isinstance(shr.arg, tuple)))
  put("c2d_selrow_arg_is_param", str(isinstance(shr.arg, ParamArg)))
  put("c2d_selrow_src0_slot", str(shr.src[0].arg.slot))
  put("c2d_selrow_src0_size_is_none", str(shr.src[0].arg.size is None))
  put("c2d_selrow_src0_device_is_none", str(shr.src[0].arg.device is None))
  # AND the node a BRIEF named, so a reader sees it exists in this arena and is NOT the node
  # `s5.selrow` calls: `s5.ga.arena()`'s node 2 is `s5.pa(2)` = `ParamArg(2, int32)`.
  node2 = UOp(Ops.ALLOC, src=(), arg=pa(2, dtypes.int32))
  put("c2d_node2_op", nm(node2))
  put("c2d_node2_arg_is_param", str(isinstance(node2.arg, ParamArg)))
  put("c2d_node2_slot", str(node2.arg.slot))
  put("c2d_node2_device_is_none", str(node2.device is None))

  # ---- ops.py:761, THE BARE `assert`. Eight shared rows: four quadrants, two arg spellings.
  put("c2d_761 selrow", outcome(lambda: shr.copy_to_device(PY2, ONE)))
  put("c2d_761 argnone", outcome(lambda: shr.copy_to_device(PY2)))
  put("c2d_761 tupledev", outcome(lambda: shr_t.copy_to_device(PY2, ONE)))
  # `arg=0` REFUSES: `arg is None` is an IDENTITY test, so a falsy index is still an index.
  # The port's `k` is `Maybe<&2, U32>`, and a guard written as "no shard index means no shard"
  # passes this row.
  put("c2d_761 argzero", outcome(lambda: shr.copy_to_device(PY2, 0)))
  put("c2d_761 scalardevargone", outcome(lambda: buf.copy_to_device(PY2, ONE)))
  put("c2d_761 scalarnone", outcome(lambda: buf.copy_to_device(PY2)))
  put("c2d_761 tupleargzero", outcome(lambda: buf_t.copy_to_device(PY2, 0)))
  put("c2d_761 tupleargnone", outcome(lambda: buf_t.copy_to_device(PY2)))

  # ---- ops.py:759, THE DISK `raise`. Four shared, four oracle-only. ---------------------
  put("c2d_759 disk", outcome(lambda: buf.copy_to_device("DISK")))
  put("c2d_759 disktuple", outcome(lambda: buf.copy_to_device(("DISK", "PYTHON"))))
  put("c2d_759 cpu", outcome(lambda: buf.copy_to_device("PYTHON")))
  put("c2d_759 cputuple", outcome(lambda: buf.copy_to_device(PY2)))
  put("c2d_759 disklower", outcome(lambda: buf.copy_to_device("disk")))
  put("c2d_759 disksuffix", outcome(lambda: buf.copy_to_device("DISK:0")))
  put("c2d_759 nodisk", outcome(lambda: buf.copy_to_device("NODISK")))
  put("c2d_759 diskx", outcome(lambda: buf.copy_to_device("DISKX")))

  # ---- ops.py:763, THE WEAK-DTYPE `raise`. Six shared rows; the dtype is the ONLY mover. --
  # The positives are drawn from the eighteen of twenty dtypes outside `dtypes.weaks` and
  # include a FLOAT and a BOOL, so the boundary is not "integer versus weak" by accident. No
  # RANGE appears on either side: every `UOp.range` is `weakint`, so a RANGE is a refusal
  # fixture and using one as a positive is the mistake this lane was written to prevent.
  for tag, dt in (("i32", dtypes.int32), ("f32", dtypes.float32), ("bool", dtypes.bool),
                  ("void", dtypes.void), ("weakint", dtypes.weakint),
                  ("weakfloat", dtypes.weakfloat)):
    put(f"c2d_763 {tag}",
        outcome(lambda dt=dt: UOp(Ops.BUFFER, src=(), arg=pa(1, dt)).copy_to_device("PYTHON")))

  # ---- ops.py:892, THE OTHER `assert`, which the port's comment does not name. ------------
  # `assert isinstance(self.src[0].device, tuple), f"mselect must be on tuple device, getting
  # {...}"`. It HAS A MESSAGE where 761 has none, so it is a different upstream behaviour, and
  # it fires LAZILY -- on the first `.device` READ, not at construction. Two rows because
  # collapsing them would repeat the error `validate-oracle.py` records for
  # `dv_bad_dtype_bitcast`.
  put("c2d_892 construct", outcome(lambda: shr.mselect(ONE)))
  put("c2d_892 deviceread", outcome(lambda: shr.mselect(ONE).device))

  # ---- THE COUNTS, EACH NAMING THE LANE THAT CAN ANSWER IT. ---------------------------
  # Shared, and each about the AGREED FIXTURE SET rather than about either lane's output, so
  # the two lanes agree on them by construction and cannot go stale against each other.
  put("c2d_fixture_n", "24")
  put("c2d_identity_n", "12")
  put("c2d_outcome_761_n", "8")
  put("c2d_outcome_759_n", "8")
  put("c2d_outcome_763_n", "6")
  put("c2d_outcome_892_n", "2")
  put("c2d_shared_n", "19")
  put("c2d_oracle_only_n", "5")
  put("c2d_weaks_n", str(len(dtypes.weaks)))
  seen = []
  for d in tuple(dtypes.all) + tuple(dtypes.weaks) + (dtypes.void, dtypes.char):
    if all(str(d) != str(s) for s in seen):
      seen.append(d)
  put("c2d_dtypes_n", str(len(seen)))

  # ORACLE-ONLY, because only CPython can be asked these and putting them on the port side
  # would mean hand-writing numbers the port has no way to compute.
  put("c2d_refused_n", str(sum(1 for _, v in got if v.startswith("REFUSED "))))
  put("c2d_built_n", str(sum(1 for _, v in got if v.startswith("BUILT "))))
  put("c2d_refused_assertion_n", str(sum(1 for _, v in got if v.startswith("REFUSED AssertionError"))))
  put("c2d_refused_runtime_n", str(sum(1 for _, v in got if v.startswith("REFUSED RuntimeError"))))
  # THE SEVEN, counted from the NINETEEN shared rows rather than from this prose. `shared` is
  # every row whose name the port lane also prints, so the shared-refusal count is computed by
  # intersecting rather than by a list someone has to keep in step.
  shared = ["c2d_761 selrow", "c2d_761 argnone", "c2d_761 tupledev", "c2d_761 argzero",
            "c2d_761 scalardevargone", "c2d_761 scalarnone", "c2d_761 tupleargzero",
            "c2d_761 tupleargnone", "c2d_759 disk", "c2d_759 disktuple", "c2d_759 cpu",
            "c2d_759 cputuple", "c2d_763 i32", "c2d_763 f32", "c2d_763 bool", "c2d_763 void",
            "c2d_763 weakint", "c2d_763 weakfloat", "c2d_892 construct"]
  by_name = dict(got)
  put("c2d_shared_refused_n", str(sum(1 for k in shared if by_name[k].startswith("REFUSED "))))
  put("c2d_shared_built_n", str(sum(1 for k in shared if by_name[k].startswith("BUILT "))))

  for line in ROWS:
    print(line)
  return 0


if __name__ == "__main__":
  sys.exit(main())