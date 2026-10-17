#!/usr/bin/env python3
"""CPython's half of `gates/specreach.bend`: the SAME three fixtures, the SAME six tables.

    .venv/bin/python gates/specreach-oracle.py

WHY A SECOND FILE AND NOT A FLAG. `gates/opseven-oracle.py` is this pattern already, and the reason
is the one `AGENTS.md` keeps restating: the two lanes must be built by DIFFERENT code from DIFFERENT
construction sites, or a diff between them compares one implementation with itself. The port mints its
GETADDR from `spec.bend`'s own `main_arena` (`O.UOp.new(..., OpsGETADDR{}, [buffer], ADev{...}, ...)`)
and this file mints it from upstream's `UOp(Ops.GETADDR, ...)`, so agreement is evidence.

THE SIX NUMBERS PER FIXTURE. `sh te sp hq sk sf` are `spec_shared/tensor/program/hcq/kernel_graph/full`
verdicts, printed as `1` True, `0` False, `9` the None that `rewrite` returns when no rule decided --
`ops.py:1605` returns the first non-`None`, and `type_verify` (`spec.py:37`) accepts only `is True`, so
`9` is a rejection that no rule owns. That is the port's `Sp.show_v` spelling and it is not a
coincidence of notation: both sides are answering "which of the three did the first-wins fold produce".

WHAT THIS FILE IS NOT. It grades nothing and holds no pins. The port's `full_table` answer for a
GETADDR is expected to DIFFER from `spec_full`'s, and the difference is the finding the reader probe
was built to make visible; a diff gate that flagged it would be grading the port against itself. The
useful reading is the PAIR of files side by side.

`bin_u8` IS REPORTED AS NOT EXERCISING `spec.py:204`. A BINARY with one src skips `spec_shared`'s
BINARY rule (which demands `src=()`), and the first `spec_program` rule is then the only candidate; if
it still answers `9` then `Ops.BINARY` is a `GroupOp.Defines` member here and `pr_0` never claims it.
The row is printed either way, because a fixture that turned out not to exercise what it was built for
is a fact about the fixture and belongs in the output rather than in a footnote.
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


def buf(dtype=dtypes.uint8, device="CPU") -> UOp:
  return UOp(Ops.BUFFER, (UOp.const(4, dtypes.int32),),
             ParamArg(0, dtype, 4, None, device, None, None, None, None))


def ga_plain() -> UOp:
  return UOp(Ops.GETADDR, (buf(),), "CPU", dtypes.uint64)


def ga_after() -> UOp:
  return UOp(Ops.GETADDR, (UOp(Ops.AFTER, (buf(),)),), "CPU", dtypes.uint64)


def bin_u8() -> UOp:
  # A CONST src and NOT a CAST, which is the whole point: `spec.py:204`'s first `spec_program` rule
  # answers `False` for "a CONST under anything but a CAST", so a CAST here would answer `None` and the
  # fixture would exercise nothing. The CONST carries int64 (upstream's `UOp.const(1)`) and the
  # BINARY's dtype FOLLOWS its `bytes` arg, so this is the same node the port builds.
  return UOp(Ops.BINARY, (UOp.const(1),), b"abcd")


TABLES = (("sh", spec_shared), ("te", spec_tensor), ("sp", spec_program), ("hq", spec_hcq),
          ("sk", spec_kernel_graph), ("sf", spec_full))


def main() -> int:
  for name, make in (("ga_plain", ga_plain), ("ga_after", ga_after), ("bin_u8", bin_u8)):
    u = make()
    cells = " ".join(f"{k}={verdict(m, u)}" for k, m in TABLES)
    print(f"{name}\t{cells}")
  return 0

# NO `if __name__ == "__main__"` GUARD, and that is deliberate rather than an omission.
# `gates/gates-pop.py` clause I DISCOVERS gates by that AST node, so a census that carries one
# becomes a gate, lands in the ledger, and turns the meta-gate red for the crime of being a
# census. `gates/opseven-oracle.py` has no guard either, and that is the house shape for an
# oracle. Run this file BY PATH; `raise SystemExit` at top level keeps the exit status.
raise SystemExit(main())
