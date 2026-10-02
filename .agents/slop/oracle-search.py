#!/usr/bin/env python
"""Oracle for tinybendygrad/codegen/opt/search.bend.

EVERY VALUE IS READ FROM LIVE CPython by importing the real `tinygrad.codegen.opt.search`
and reading `actions`. Nothing is transcribed. See .agents/slop/agent-core.md, "Generate
every py= expectation BY CALLING CPYTHON. Never type one." -- five units were burned by
hand-typing, and one shipped a gate green over a number that was wrong in BOTH the port
and the oracle.

Two runs, because `actions` is built at MODULE IMPORT TIME from `getenv("BEAM_PADTO", 0)`:

    .venv/bin/python .agents/slop/oracle-search.py                 > search.oracle.txt
    BEAM_PADTO=1 .venv/bin/python .agents/slop/oracle-search.py   > search.oracle-padto.txt

and merge base-first, padto-only-names-second (`merge-oracle.py` does it and asserts no
name is defined twice with two different values).

Exit path: this file refuses to print a partial row set. An oracle that emitted 0 rows and
exited 1 while the gate printed 432 rows is a recorded failure, so `emit` asserts its own
expected row count before writing anything.

WHY THE SHAPE ROWS EXIST. `acts_n` alone is satisfied by a table with the right SIZE and
the wrong SET: a dropped class, a dropped enum member, a swapped default and a reordered
field all print 209. Each row below is annotated with the wrong set it separates.
"""
import os
import sys
import collections

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from tinygrad.uop.ops import AxisType
from tinygrad.codegen.opt import OptOps
import tinygrad.codegen.opt.search as S

ACTS = S.actions
ROWS = []
PADTO = bool(os.environ.get("BEAM_PADTO"))


def row(name, value):
  ROWS.append(f"{name}={value}")


# ---------------------------------------------------------------------------
# helpers over the REAL table
# ---------------------------------------------------------------------------
def is_split(o):
  return o.op is OptOps.SPLIT


def tgt(o):
  """The AxisType a SPLIT targets, or None."""
  return o.arg[1] if is_split(o) and isinstance(o.arg, tuple) and len(o.arg) > 1 else None


def top(o):
  return bool(o.arg[2]) if is_split(o) and isinstance(o.arg, tuple) and len(o.arg) > 2 else False


def amt(o):
  return o.arg[0] if is_split(o) and isinstance(o.arg, tuple) else None


def by_name(n):
  return [o for o in ACTS if o.op.name == n]


def tgt_group(tname):
  """Every SPLIT whose target axis type is `tname`."""
  return [o for o in ACTS if is_split(o) and tgt(o) is not None and tgt(o).name == tname]


# ---------------------------------------------------------------------------
# THE SIZE, AND THE SIZE WITH BEAM_PADTO
# ---------------------------------------------------------------------------
# `acts_n` IS THE BASE CONFIG'S ROW and the padto run must not define it: with
# BEAM_PADTO=1 the table is genuinely 216, so a merge that let both runs write the name
# would see a conflict and, if it resolved the conflict by taking the second file, would
# report a padto fact as if it were the base row. Same reason `byop_padto` is base-only.
if PADTO:
  row("acts_n_padto", len(ACTS))
  row("grp_padto", len(by_name("PADTO")))
else:
  row("acts_n", len(ACTS))

# ---------------------------------------------------------------------------
# THE GROUP SIZES -- one row per group of search.py's eight comprehensions, read as a
# GROUP rather than counted, because a group is what a comprehension is.
# ---------------------------------------------------------------------------
up_f = [o for o in tgt_group("UPCAST") if not top(o)]
lcl_f = [o for o in tgt_group("LOCAL") if not top(o)]
lcl_t = [o for o in tgt_group("LOCAL") if top(o)]
row("grp_up", len(up_f))
row("grp_lcl_top", len(lcl_t))
# `SPLIT(0, (32, LOCAL))` is search.py:19, spliced in as ITS OWN statement rather than
# as part of the LOCAL comprehension at :16, so it is its own group -- and `amt == 32`
# is what separates it, because 32 is not in the comprehension's amt list
# [0,2,3,4,8,13,16,29] and the amt-32 LOCAL entries that DO share it all carry top=True.
# Splitting on `axis == 0` would NOT work: both groups have an axis-0 entry.
SPLIT32 = [o for o in ACTS if is_split(o) and tgt(o) is not None
           and tgt(o).name == "LOCAL" and not top(o) and amt(o) == 32]
row("grp_split32", len(SPLIT32))
row("grp_lcl", len(lcl_f) - len(SPLIT32))
# The two TC groups are separated by the SECOND ARG ELEMENT, not by the axis:
# search.py:20 is `TC(0, (-1, 0, TC))` and :22 is `TC(axis, (-1, TC_OPT, TC))` for
# axis in range(9) -- which INCLUDES axis 0, so splitting on the axis gives 2 and 8
# and answers a question nobody asked.
row("grp_tc0", len([o for o in by_name("TC") if o.arg[1] == 0]))
row("grp_tc", len([o for o in by_name("TC") if o.arg[1] != 0]))
row("grp_swap", len(by_name("SWAP")))

# ---------------------------------------------------------------------------
# THE CENSUS. `tgt_kinds` is the number of distinct SPLIT TARGET AXIS TYPES, and it is
# the row the deleted UNROLL group is really about: UNROLL was a third target, so a
# rebase that reinstates it (as UNROLL or under any other name) moves this 2 -> 3. A
# rebase that swaps the 60 gone entries for a new 60-entry group of a DIFFERENT target
# LEAVES acts_n at 209 -- this is the only row that moves.
# ---------------------------------------------------------------------------
kinds = sorted({t.name for t in (tgt(o) for o in ACTS) if t is not None})
row("tgt_kinds", len(kinds))
# Per-target totals, under the gate's own names. Together with tgt_split they name the
# SET and its two SIZES, so an entry moved BETWEEN the two targets is caught even
# though both totals hold.
for tname, rname in (("UPCAST", "up"), ("LOCAL", "lcl")):
  row(f"tgt_{rname}", len(tgt_group(tname)))
row("tgt_split", len([o for o in ACTS if is_split(o)]))

# Per-OptOps totals, under the gate's own names. Catches the reshuffle a target census
# cannot see: the two TC entries and the ten SWAPs are different OptOps carrying
# different arg shapes, so a TC that became a SWAP leaves acts_n, tgt_split and every
# tgt_* row untouched.
for opname, rname in (("SPLIT", "split"), ("TC", "tc"), ("SWAP", "swap"), ("PADTO", "padto")):
  if PADTO and rname == "padto":
    continue  # `byop_padto` is the BASE config's row and equals 0 there; the padto run
              # must not define it too, or the two runs disagree on one name and the
              # merge has to pick a winner. The padto count is `grp_padto` above.
  row(f"byop_{rname}", len(by_name(opname)))

# ---------------------------------------------------------------------------
# THE amt-0 CENSUS -- what pins IDENTITY rather than size. Only UPCAST and LOCAL have an
# amt-0 entry, so zero_n_up and zero_n_lcl ARE the two identities: no arrangement of
# `amt = 0` over a different target leaves both at 10 and 8 while the group sizes hold.
# zero_max_* is the highest axis that HAS a twin, reported so the exclusive bound the
# ladder needs and the highest axis it must admit can be compared by name -- and so a
# refactor that feeds `zero_max` to the ladder instead of `zero_n` shows as a red row
# rather than as a silently off-by-one ladder.
# ---------------------------------------------------------------------------
zero = [o for o in ACTS if is_split(o) and amt(o) == 0]
row("acts_zero", len(zero))
for tname, rname in (("UPCAST", "up"), ("LOCAL", "lcl")):
  axes = sorted(o.axis for o in zero if tgt(o).name == tname)
  row(f"zero_n_{rname}", len(axes))
  row(f"zero_max_{rname}", max(axes))
# No amt-0 entry carries top=True, which is what makes zero_variant's True arm False.
row("zero_top_n", len([o for o in zero if top(o)]))

# THE LADDER'S OWN ROWS, one per probed (axis type, top, axis), named exactly as the gate
# names them. Each is CPython's answer to `replace(o, arg=(0,)+o.arg[1:]) in actions`,
# computed by Python's own `in` over the real list -- not by a Bend-shaped
# reimplementation, because a port and an oracle that share a shape share every error in
# it (`nv_query_litter` said 2 in both; the truth was 3).
def twin(o):
  """`replace(o, arg=(0,)+o.arg[1:]) in actions`, answered by Python's own `in`."""
  zeroed = type(o)(op=o.op, axis=o.axis, arg=(0,) + tuple(o.arg[1:]))
  return zeroed in ACTS


PROBES = [("UPCAST", False, 0, "zero_up0"), ("UPCAST", False, 9, "zero_up9"),
          ("UPCAST", False, 10, "zero_up10"), ("LOCAL", False, 7, "zero_lcl7"),
          ("LOCAL", False, 8, "zero_lcl8"), ("LOCAL", False, 9, "zero_lcl9"),
          ("LOCAL", True, 0, "zero_top0"), ("LOCAL", True, 9, "zero_top9")]
for tname, tp, a, rname in PROBES:
  hit = [o for o in ACTS
         if is_split(o) and tgt(o) is not None and tgt(o).name == tname
         and top(o) is tp and o.axis == a]
  row(rname, int(any(twin(o) for o in hit)))

# ---------------------------------------------------------------------------
# THE DELETED MEMBERS. The old rows `zero_un9` / `zero_red0` asked the Bend ladder about
# `AxisType.UNROLL` / `AxisType.REDUCE`, which upstream no longer has, so they could
# never disagree with CPython. These are the replacements' provenance: the member is
# absent from the enum, absent from the table, and no `amt = 0` entry targets it.
# ---------------------------------------------------------------------------
for dead in ("REDUCE", "UNROLL"):
  row(f"dead_{dead}_in_enum", int(hasattr(AxisType, dead)))
  row(f"dead_{dead}_in_actions", int(dead in kinds))
row("axis_types_n", len(list(AxisType)))


def emit():
  # 30 gate rows (the 6 beam rows -- `dropped`, `drop_ok`, `drop_seen`, `keep_ok`,
  # `least_lo`, `least_hi` -- are the port's own SCORE-table decisions, not CPython
  # facts) + 5 provenance rows (`dead_*`, `axis_types_n`). BOTH runs emit 35: the padto
  # run swaps `acts_n` and `byop_padto` for `acts_n_padto` and `grp_padto`, so neither
  # name is defined twice. The count is asserted so a truncated run cannot be mistaken
  # for a passing one -- an oracle that emitted 0 rows and exited 1 while the gate
  # printed 432 rows is a recorded failure in this project.
  EXPECT = 35
  if len(ROWS) != EXPECT:
    print(f"ORACLE ROW COUNT WRONG: got {len(ROWS)} want {EXPECT}", file=sys.stderr)
    print("\n".join(ROWS), file=sys.stderr)
    return 2
  print("\n".join(ROWS))
  return 0


if __name__ == "__main__":
  sys.exit(emit())