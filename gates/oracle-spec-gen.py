#!/usr/bin/env python3
"""The GENERATOR of `oracles/oracle-spec.rows`, and the checker of the same file.

    .venv/bin/python gates/oracle-spec-gen.py                       # print the rows
    .venv/bin/python gates/oracle-spec-gen.py --check               # compare with the file
    .venv/bin/python gates/oracle-spec-gen.py --out oracles/oracle-spec.rows

WHY A GENERATOR AND NOT A HAND-EDIT. The rows are what CPython's `tinygrad/uop/spec.py`
SAYS, and every one of them is a fact about a table that upstream can move: the six table
sizes, the two `early_reject` sets, and the three verdicts. A hand-edit is a FROZEN COPY
of a reading, and a frozen copy of a reading is the defect this whole class is about --
`AGENTS.md` calls it "a population is a generator's own declaration, loaded by path". The
generator this file replaces (`.agents/slop/rebase-oracle-spec.py`) is GONE, and the file it
wrote was left behind at the values the port had when the port was one rule short of
upstream: `33/55/42/35/70` where upstream says `34/56/43/36/71`. So the file was not wrong
BY HAND, it was stale, and the way to say that is to regenerate it.

THE SIX SIZES ARE NOT ALL `len()`. `PatternMatcher` has no `len()` and every CPython spec
table is a `PatternMatcher([...]) + spec_shared` CONCATENATION, so the six rows are:

    sh_len  len(spec_shared)                                    -- 34
    te_len  len(spec_tensor)                                    -- 56
    pr_len  len(spec_program)                                   -- 43
    hq_len  len(spec_hcq)                                       -- 36
    fu_len  len(spec_full) - 2*len(spec_shared)                -- 71
    kg_len  len(spec_kernel_graph)                              -- 13

`fu_len` IS THE SUBTRACTION THAT SURVIVES THE CONCATENATION. `spec_full` names
`spec_shared` THREE times -- once through `spec_tensor`, once through `spec_program`, once
through `spec_hcq` -- and only the FIRST is reachable, because the fold is first-wins: a
rule that skipped in the first block skips again in the second, and a rule that answered has
already stopped the fold. So `len(spec_full.patterns)` is 139 and the REACHABLE count is
`4 + 22 + 34 + 9 + 2 = 71`, which is what the port's linear `full_table()` has to answer.
`own(pm, base) = len(pm) - len(base)` is the subtraction, and it is the same one the
`#repro_*` rows below state.

THE `tag_*` ROWS ARE THE PORT'S ROW NAMES, and the value is CPython's ANSWER to the
question each of them asks. `tag_const` is the port's `t_tag_const`: does upstream's CONST
rule claim `Ops.CONST` and carry an EMPTY `early_reject`? `tag_rej` is the port's
`t_tag_rej`: does upstream's shared rule 15 reject on `RANGE`, and does upstream's
four-source PROGRAM rule reject on four ops? A row that reads `0` is the port and upstream
DISAGREEING, and that is the row that can go red.

NO `if __name__ == "__main__"` GUARD, ON PURPOSE. `gates/gates-pop.py` clause I DISCOVERS
gates by that AST node, so a script WITH the guard becomes a gate, lands in the ledger, and
turns the meta-gate red for the crime of being a census. This file is a census and a
generator, not a gate: it grades nothing. Run it BY PATH; `raise SystemExit` at top level
keeps the exit status.
"""
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ORACLE = ROOT / "oracles" / "oracle-spec.rows"


def _verdict(m, u) -> int:
  """`1` is True, `0` is False, `9` is Python's `None` -- the port's `Sp.show_v` spelling."""
  ret = m.rewrite(u)
  return 9 if ret is None else (1 if ret is True else 0)


def rows() -> list[str]:
  """Every row of the oracle, computed from CPython's LIVE `tinygrad.uop.spec`."""
  from tinygrad.dtype import dtypes
  from tinygrad.uop.ops import Ops, UOp
  from tinygrad.uop.spec import spec_full, spec_hcq, spec_kernel_graph, spec_program, spec_shared, spec_tensor

  n_shared = len(spec_shared.patterns)
  n_tensor = len(spec_tensor.patterns)
  n_program = len(spec_program.patterns)
  n_hcq = len(spec_hcq.patterns)
  n_full = len(spec_full.patterns)
  n_kg = len(spec_kernel_graph.patterns)
  # `own(pm, base)`: the table's OWN literal, before the `+ spec_shared` concatenation.
  own_tensor = n_tensor - n_shared
  own_program = n_program - n_shared
  own_hcq = n_hcq - n_shared
  own_full = n_full - n_tensor - n_program - n_hcq
  # the REACHABLE count of `spec_full`: `spec_shared` appears three times and only the
  # first is reachable, so the two later copies are dead.
  fu_len = own_full + own_tensor + own_program + own_hcq + n_shared

  # the port's `t_tag_const`: upstream's CONST rule claims CONST and rejects nothing.
  const_pat = spec_shared.patterns[2][0]
  tag_const = int(const_pat.op == (Ops.CONST,) and not const_pat.early_reject)
  # the port's `t_tag_rej`: upstream's shared rule 15 rejects on RANGE, and upstream's
  # four-source PROGRAM rule rejects on four ops.
  shared_rej = spec_shared.patterns[15][0].early_reject
  four_src = spec_tensor.patterns[own_tensor - 1][0]
  tag_rej = int(shared_rej == {Ops.RANGE} and len(four_src.early_reject) == 4)

  # the shared table's own non-empty `early_reject` set, as `index:ops`.
  shared_rejects = [(i, sorted(o.name for o in p.early_reject))
                     for i, (p, _) in enumerate(spec_shared.patterns) if p.early_reject]

  sink = UOp(Ops.SINK, (), None)
  noop = UOp(Ops.NOOP, (), None)

  def ops(names) -> str:
    return "|".join(sorted(names))

  return [
    f"sh_len={n_shared}",
    f"te_len={n_tensor}",
    f"pr_len={n_program}",
    f"hq_len={n_hcq}",
    f"fu_len={fu_len}",
    f"kg_len={n_kg}",
    f"tag_const={tag_const}",
    f"tag_rej={tag_rej}",
    f"#repro_four_src_rule_op={ops(o.name for o in four_src.op)}",
    f"#repro_four_src_reject={ops(o.name for o in four_src.early_reject)}",
    f"#repro_tensor_own_n={own_tensor}",
    f"#repro_spec_full_own={own_full}",
    "#repro_shared_rejects=" + ",".join(f"{i}:{ops(v)}" for i, v in shared_rejects),
    f"sink_ok={_verdict(spec_shared, sink)}",
    f"noop_ok={_verdict(spec_shared, noop)}",
    f"noop_kg={_verdict(spec_kernel_graph, noop)}",
  ]


def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("--check", action="store_true", help="compare with the file and exit 1 on drift")
  ap.add_argument("--out", type=Path, help="write the rows here")
  args = ap.parse_args()
  text = "\n".join(rows()) + "\n"
  if args.check:
    if not ORACLE.exists():
      print(f"REFUSED: {ORACLE.relative_to(ROOT)} does not exist")
      return 3
    cur = ORACLE.read_text()
    if cur == text:
      print(f"OK: {ORACLE.relative_to(ROOT)} is the generator's output, byte for byte")
      return 0
    print(f"DRIFT: {ORACLE.relative_to(ROOT)} is not the generator's output")
    for a, b in zip(cur.splitlines(), text.splitlines()):
      if a != b:
        print(f"  file: {a}\n  gen : {b}")
    return 1
  if args.out:
    args.out.write_text(text)
    print(f"wrote {args.out}")
  else:
    print(text, end="")
  return 0

# NO `if __name__ == "__main__"` GUARD, and that is deliberate rather than an omission.
# `gates/gates-pop.py` clause I DISCOVERS gates by that AST node, so a census that carries one
# becomes a gate, lands in the ledger, and turns the meta-gate red for the crime of being a
# census. Run this file BY PATH; `raise SystemExit` at top level keeps the exit status.
raise SystemExit(main())
