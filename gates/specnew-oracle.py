#!/usr/bin/env python3
"""CPython's half of `gates/specnew.bend`: the SAME two fixtures, the SAME six tables.

    .venv/bin/python gates/specnew-oracle.py

WHY A SECOND FILE AND NOT A FLAG. `gates/specreach-oracle.py` is this pattern already, and
the reason is the one `AGENTS.md` keeps restating: the two lanes must be built by DIFFERENT
code from DIFFERENT construction sites, or a diff between them compares one implementation
with itself. The port mints its AFTER and its STORE from `ops.bend`'s own constructors and
this file mints them from upstream's `UOp`, so agreement is evidence.

THE TWO FIXTURES, and each one is a node shape the port REJECTED before 2026-10-22:

  after_alu  `AFTER(ADD(1, 2))` -- upstream's `spec.py:104` ACCEPTS it, because the AFTER's
              src[0] is an ALU and its shape is `()`. Upstream's `spec.py:99` rule does not
              claim it: an ADD is not a movement op, so that rule does not MATCH and the
              scan goes on.
  store_bad  `STORE(BUFFER(int32), CAST(CONST(1), int64))` -- the value's dtype does NOT
              match the target's, so upstream's `spec.py:125` answers `False`. The value is
              int64 and not weakint on purpose: `weak_dtype(int32)` is weakint, so a weak
              value would MATCH the target and the rule would have nothing to say.

THE SIX NUMBERS PER FIXTURE are `sh te sp hq sk sf` -- `spec_shared`, `spec_tensor`,
`spec_program`, `spec_hcq`, `spec_kernel_graph`, `spec_full` -- printed as `1` True, `0`
False, `9` the `None` that `rewrite` returns when no rule decided. `ops.py:1605` returns the
first non-`None` and `type_verify` accepts only `is True`, so `9` is a rejection that no
rule owns. That is the port's `Sp.show_v` spelling and it is not a coincidence of notation:
both sides are answering "which of the three did the first-wins fold produce".

`sp` IS 0 FOR THE AFTER FIXTURE AND THAT IS UPSTREAM'S ANSWER, NOT A PORT DEFECT:
`spec.py:205`'s second rule says a WEAK dtype is not allowed in a program, and the AFTER
carries `dtypes.weakint` because `UOp.const(1)` is weakint.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from tinygrad.dtype import dtypes  # noqa: E402
from tinygrad.uop.ops import Ops, ParamArg, UOp  # noqa: E402
from tinygrad.uop.spec import spec_full, spec_hcq, spec_kernel_graph, spec_program, spec_shared, spec_tensor  # noqa: E402


def verdict(m, u: UOp) -> int:
  ret = m.rewrite(u)
  return 9 if ret is None else (1 if ret is True else 0)


def after_alu() -> UOp:
  c1 = UOp.const(1)
  c2 = UOp.const(2)
  return UOp(Ops.AFTER, (UOp(Ops.ADD, (c1, c2)),))


def store_bad() -> UOp:
  buf = UOp(Ops.BUFFER, (UOp.const(4, dtypes.int32),),
            ParamArg(0, dtypes.int32, 4, None, "CPU", None, None, None, None))
  val = UOp(Ops.CAST, (UOp.const(1),), dtypes.int64)
  return UOp(Ops.STORE, (buf, val))


TABLES = (("sh", spec_shared), ("te", spec_tensor), ("sp", spec_program), ("hq", spec_hcq),
          ("sk", spec_kernel_graph), ("sf", spec_full))


def main() -> int:
  for name, make in (("after_alu", after_alu), ("store_bad", store_bad)):
    u = make()
    for key, m in TABLES:
      print(f"{name}_{key}={verdict(m, u)}")
  return 0

# NO `if __name__ == "__main__"` GUARD, and that is deliberate rather than an omission.
# `gates/gates-pop.py` clause I DISCOVERS gates by that AST node, so a census that carries one
# becomes a gate, lands in the ledger, and turns the meta-gate red for the crime of being a
# census. Run this file BY PATH; `raise SystemExit` at top level keeps the exit status.
raise SystemExit(main())
