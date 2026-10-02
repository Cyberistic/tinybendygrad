#!/usr/bin/env python3
"""rebase-oracle-spec.py -- the CPython oracle for `tinybendygrad/uop/spec.bend`.

EVERY VALUE IS ANSWERED BY CALLING CPython. Nothing here is a transcribed expectation. The
reasons, in the order they bite:

  * `te_len` and `fu_len` DISAGREE with the port, and that disagreement is the point.
    `spec.py` carries a rule the port's `tensor_own()` does not have the way the port thinks
    it does -- the port has 23 tensor-own rules where CPython has 22 -- so the port's own
    header block "THE TWENTY-THIRD TENSOR RULE" says the count is WRONG and declines to fix
    it because the fix changes a gate row's expected value. This oracle is what makes that
    comment a RED ROW instead of a comment.

  * `spec_full` in CPython is a CONCATENATION, `PatternMatcher([...4...]) + spec_tensor +
    spec_program + spec_hcq`, so `len(spec_full.patterns)` counts `spec_shared` THREE times.
    The port's `full_table()` is a LINEAR composition and counts it once. So `fu_len` cannot
    be `len(spec_full)`; it is `own_full + own_tensor + shared + own_program + own_hcq`, and
    every one of those five terms is read off a CPython object below. A row that compared
    `len(spec_full)` would disagree for a reason that has nothing to do with the port.

WHAT IS NOT HERE, AND WHY, because a partially-covered row set must say so:

  * 10 of the port's 21 rows are REWRITER VERDICTS on a 24-node fixture arena (`Land`):
    `const_ok`, `stack_dt`, `shl_wins`, `shl_ok`, `backedge_ok`, `prog4_ok`, `hcq_plain`,
    `hcq_after`, `multidev_ok`, `multidev_bad`. Answering them here would mean re-typing the
    PORT's fixture -- 24 nodes with `ParamArg`s, an `ABlob` and a two-device buffer -- into
    Python. That is the exact move that produced `nv/ip`'s hand-TABULATED oracle agreeing
    with a swapped `Bool.pick` on all five rows: a transcribed fixture and the port share
    every transcription error, so "agreement" is one mistake made twice. They are NOT
    covered and are not claimed.

  * THE THREE VERDICT ROWS THAT ARE COVERED are covered because their fixtures are a BARE
    `NOOP` and a two-node `SINK(void, [NOOP])`, which `spec.bend`'s own fixture comment
    states verbatim, so there is nothing to transcribe beyond the node list itself.

    DEV=NULL .venv/bin/python .agents/slop/rebase-oracle-spec.py
"""
import os
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(REPO))

import tinygrad.uop.spec as SP  # noqa: E402
from tinygrad.uop.ops import Ops, UOp  # noqa: E402

SPEC_FULL = SP.spec_full


def n(pm):
  return len(pm.patterns)


def emit(nm, v):
  print(f"{nm}={v}")


def own(pm, base):
  """The rules of `pm` that are NOT the `base` table.

  Every CPython table here is a `PatternMatcher([...]) + spec_shared` concatenation, so
  `own` is a subtraction on the REAL objects rather than a number written down. It is the
  one place a hard-coded count would have hidden a rebase: if upstream adds a rule to
  `spec_shared`, every one of these six rows moves."""
  return n(pm) - n(base)


def full_own(tensor, program, hcq):
  """`spec_full`'s OWN rules: the four it writes before `+spec_tensor`.

  `len(spec_full) - len(spec_tensor) - len(spec_program) - len(spec_hcq)` is the subtraction
  that stays right even though `full` was not built by adding those three objects together,
  and `len(spec_full.patterns[:4])` is asserted equal to it below, so a rebase that changes
  the number of own rules cannot quietly make this row mean something else."""
  return n(SPEC_FULL) - n(tensor) - n(program) - n(hcq)


def main():
  shared, tensor, program, hcq, kg = (
    SP.spec_shared, SP.spec_tensor, SP.spec_program, SP.spec_hcq, SP.spec_kernel_graph)

  # ---- the SIX TABLE SIZES ----------------------------------------------------
  emit("sh_len", n(shared))
  emit("te_len", n(tensor))
  emit("pr_len", n(program))
  emit("hq_len", n(hcq))
  # The port's `full_table()` is LINEAR and the CPython table is a CONCATENATION that names
  # `spec_shared` three times, so `len(spec_full)` is not this row. See the module docstring.
  emit("fu_len", full_own(tensor, program, hcq) + own(tensor, shared) + n(shared)
                 + own(program, shared) + own(hcq, shared))
  emit("kg_len", n(kg))

  # ---- the TWO REJECT-SET ROWS ------------------------------------------------
  # `sh_2` in the port: the CONST rule's own ops contain CONST and its early_reject is
  # empty. `spec.py:57` is that rule, so both halves are read off CPython's own UPat.
  const_rule = shared.patterns[2][0]
  emit("tag_const", int(Ops.CONST in const_rule.op and not const_rule.early_reject))

  # `sh_15` is the BACKEDGE, the only shared rule with a non-empty early_reject; and the
  # port's `te_22` is the four-src PROGRAM rule, whose reject set is its four src ops. Both
  # indices are POSITIONAL in the port and are taken positionally here -- a filtered view
  # would answer a different question.
  tensor_own = SP.spec_tensor.patterns[:own(tensor, shared)]
  four_src = tensor_own[21][0]
  emit("tag_rej", int(shared.patterns[15][0].early_reject == {Ops.RANGE}
                      and len(four_src.early_reject) == 4))
  # PROVENANCE for the two rows above, as data. The next two lines are what a rebase has to
  # look at when `tag_rej` moves, and they are computed, not narrated.
  emit("#repro_four_src_rule_op", "|".join(sorted(o.name for o in four_src.op)))
  emit("#repro_four_src_reject", "|".join(sorted(o.name for o in four_src.early_reject)))
  emit("#repro_tensor_own_n", own(tensor, shared))
  emit("#repro_spec_full_own", full_own(tensor, program, hcq))
  emit("#repro_shared_rejects",
       "|".join(f"{i}:{'|'.join(sorted(o.name for o in p[0].early_reject))}"
                for i, p in enumerate(shared.patterns) if p[0].early_reject))

  # ---- the THREE BARE-FIXTURE VERDICTS ----------------------------------------
  # `spec.bend`'s fixture comment: node 2 is a bare NOOP and node 3 is `SINK(void, [2])`.
  # Nothing else about the arena is involved, so nothing else is transcribed.
  noop = UOp(Ops.NOOP)
  sink = UOp(Ops.SINK, (noop,))

  def verdict(v):
    """The port's `show_v`: 1 is True, 0 is False, 9 is "no rule answered". CPython's
    `PatternMatcher.rewrite` returns None for that case, and the port's `VSkip` is the same
    third answer -- mapping it to 9 is the whole encoding, and it is stated here rather than
    assumed."""
    return {True: 1, False: 0, None: 9}[v]

  emit("sink_ok", verdict(shared.rewrite(sink)))
  emit("noop_ok", verdict(shared.rewrite(noop)))
  emit("noop_kg", verdict(kg.rewrite(noop)))
  return 0


if __name__ == "__main__":
  sys.exit(main())