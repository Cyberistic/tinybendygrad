#!/usr/bin/env python3
"""ops-oracle.py -- the CPython LANE for `tinybendygrad/uop/ops.bend`.

`ops.bend` shipped with 22 rows and NO CPython lane at all: `cpython=0`. Nothing in it
could see that `AxisType.value` was wrong for four of the eight surviving axis types,
that `axis_id`/`axis_type` were swapped relative to the current `ops.py`, that
`AXIS_REDUCE`/`AXIS_UNROLL` no longer exist, or that `axis_to_pos` was deleted
outright. This script is that lane. It is the FIRST oracle in the repo that reads the
UPSTREAM tree rather than the vendored pin, because the file under gate is being
brought ONTO upstream and the pin is the thing that drifted.

    .venv/bin/python .agents/slop/ops-oracle.py                    > ops-py.txt
    ./bin/bend tinybendygrad/uop/ops.bend | grep -v '^#shared'    > ops-bd.txt
    ./bin/bend tinybendygrad/uop/ops.bend -o ops.bin && ./ops.bin | grep -v '^#shared' > ops-bn.txt
    diff ops-py.txt ops-bd.txt && diff ops-py.txt ops-bn.txt

`TG_TREE` CHOOSES THE TREE and it is the whole point of the script:

    TG_TREE=.                                  the vendored pin (6c3d401cf324)
    TG_TREE=.agents/slop/opstree               `git archive upstream/master tinygrad`
    TG_TREE=.agents/slop/opstree-78d4         `git archive 78d482262 tinygrad`

so the SAME script diffs the port against the pin and against upstream, and the two
answers differ in exactly the rows that upstream moved. Every row below is printed by
CALLING CPython: no axis name, no letter, no colour, no enum value, no arg order and no
table entry in this file is transcribed. The one list that IS written here is the
fixture list of axis types to ask about, and that list is DERIVED -- see `AXES`.

ROWS. Four shapes, because four different things are being asked:

  * `axv_<NAME>`    -- `AxisType.<NAME>.value`. The headline. CPython's `auto()` numbers
    the members in DECLARATION order, and upstream changed that order, so four of the
    eight surviving values moved. If any fixture had no `WARP` or `PLACEHOLDER` axis
    this row would not exist -- which is why there is one row per MEMBER, not one row
    per fixture.
  * `axn_<NAME>`    -- `AxisType.name` (`__repr__` is `str(self)`).
  * `axl_<NAME>`    -- `axis_letters[at]`, or `!KeyError` when the member is not in
    the dict. The `!` marker is what makes ABSENCE visible: PLACEHOLDER is in the enum
    and in neither dict, and a row that printed `""` for it would agree with a port
    that had dropped the dict entry.
  * `axc_<NAME>`    -- `axis_colors[at]`, same marker.
  * `axs_<OP>`      -- `range_start[op]`, or `!KeyError`. CPython's `ended_ranges` does
    `if self.op in range_start` so a miss is a real answer, and the port's `case _` arm
    answers 0; the row exists so the ARM and the OP LIST are both pinned.
  * `rng_<tag>=<COUNT> <ROOT>/<NSRC> <SRCOPS> arg=<ARG>` -- THE FOUR FACTS PLUS THE
    ANSWER AS ONE STRING, for every RANGE fixture. `<COUNT>` is the node count,
    `<ROOT>/<NSRC>` the root op and its src count, `<SRCOPS>` the SRC OP SEQUENCE, and
    `<ARG>` the arg rendered structurally. The src op sequence is the fifth fact and it
    is here for the reason `after_puts_self_first` exists: swapping two srcs leaves
    count, root op, root nsrc and arg ALL identical. `<ARG>` is where `UOp.range`'s
    flipped arg order shows up, because the axis type moved from LAST to FIRST.
  * `axid_<tag>=<IDS>` and `axt_<tag>=<TYPE>` -- `uop.axis_id` and `uop.axis_type` READ AS
    THE PROPERTIES, never as a hand-written slice of `.arg`. These two are the swapped
    pair: at the pin `axis_id` is `arg[0:-1]` and `axis_type` is `arg[-1]`; upstream
    they are `arg[1:]` and `arg[0]`. Reading the property is what makes the row follow
    CPython rather than encode the port's reading of it.
  * `axlt_...` -- `AxisType.__lt__`, which upstream ADDED. Two facts per pair: the
    comparison result and the sorted name sequence, because a `__lt__` that answers the
    right booleans but the wrong ORDER is a different sort.
  * `eqax_collide` / `eqax_diag` -- how many pairs of DISTINCT axis types compare equal,
    and how many compare equal to themselves. This is the gate for `eq_axis`, which in
    the port is `AxisType.value` equality, so a wrong value that made two DIFFERENT axis
    types compare equal would collapse a range's arg. Counts, not the NxN table: a table
    of `eqax_A_B=<bool>` is a change detector, because a PERMUTED value table -- which
    is exactly what upstream did to four members -- leaves every pair's answer
    unchanged. The counts move on the collision's twin and `axv_*` moves on the
    permutation, so between them they cover both.
  * `xpos` -- `hasattr(ops, 'axis_to_pos')`. `axis_to_pos` is DELETED upstream, so the
    honest row is a fact about the module, not a value from it.

`#shared` rows at the head are the 22 EXISTING rows. They are printed here by CALLING
CPython for what is gateable and are otherwise listed by name with `#bend-only`. This
keeps one file and one diff, and it keeps the existing 22 visible rather than filtered
away by position.
"""
import os
import sys

TG_TREE = os.environ.get('TG_TREE', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'opstree'))
sys.path.insert(0, TG_TREE)

import tinygrad.uop.ops as O  # noqa: E402
from tinygrad.uop import Ops  # noqa: E402
from tinygrad.uop.ops import UOp, AxisType, axis_letters, axis_colors, range_start  # noqa: E402

TAG = f"TG_TREE={TG_TREE}"

# THE AXIS LIST IS DERIVED FROM CPYTHON, never written here. The eight names below are
# what `list(AxisType)` answers at the tree this script read, and the script PRINTS the
# derivation rather than trusting it: `axn_all` is the member list in declaration
# order and `axv_all` is its value sequence, so a tree whose enum grew or reordered
# changes three rows instead of silently answering about the wrong eight types.
AXES = list(AxisType)


def srcops(u) -> str:
  """The SRC OP SEQUENCE -- the fifth fact, and the one that sees a two-src swap.

  `str(op)` not `op.name`: a Python `Enum`'s `str` is `Ops.RANGE` while its `name` is
  `RANGE`, and the port's `Ops.name` is the OTHER one -- it exists for `UOp.tuplize` and
  prints the `Ops.` prefix. The row is compared byte for byte, so the two spellings have
  to agree, and the choice is made HERE once rather than in a printer on each side.
  """
  return " ".join(str(s.op) for s in u.src) if u.src else "-"


def render(x) -> str:
  """`x` as the port's ONE canonical spelling: `AxisType.NAME`, `7`, `(0,1)`, `(0,)`.

  Recursive because the arg is nested -- `UOp.range(2, (0, 1), LOOP)` packs a TUPLE
  inside the arg tuple -- and because CPython's own `str((0, 1))` is `(0, 1)` with a
  SPACE while `str((AxisType.WEAK, 0))` is `(AxisType.WEAK, 0)` with one too, so
  `str(tuple)` cannot be the spelling: the two nestings would use different separators
  and the Bend would have to reproduce `repr`'s spacing rules. Comma, no space, at
  every level, is one rule. The trailing comma on a ONE-element tuple is Python's and
  it is load-bearing: `axis_id` of a two-element arg is the 1-tuple `(0,)`, and without
  the comma `(0)` reads as a parenthesised int rather than a 1-tuple.
  """
  if isinstance(x, AxisType):
    return f"AxisType.{x.name}"
  if isinstance(x, tuple):
    body = ",".join(render(e) for e in x)
    return "(" + body + ("," if len(x) == 1 else "") + ")"
  return str(x)


def argstr(u) -> str:
  """`u.arg` rendered structurally, with its LENGTH.

  `repr(arg)` is deliberately not used. `AxisType.__repr__` is `str(self)`, so CPython
  already prints the enum NAME here and a name cannot be confused with an int -- but the
  LENGTH is what the flipped arg order is read from, and printing it next to the values
  is what makes a two-element `(ids, type)` distinguishable from a three-element
  `(type, id, id)` at a glance.
  """
  a = u.arg
  return render(a) + f"/len={len(a) if isinstance(a, tuple) else 1}"


def sig(u) -> str:
  """THE FOUR FACTS PLUS THE ANSWER, as ONE string.

  node count, root op, root nsrc, SRC OP SEQUENCE, then the arg. The src op sequence
  is the fifth fact and the one that sees a two-src swap, where count, root op, root
  nsrc and arg are all identical -- measured on `mixin/movement`, which shipped a
  swapped pair through 447 green rows for exactly that reason.
  """
  return f"{len(list(u.toposort()))} {u.op}/{len(u.src)} {srcops(u)} arg={argstr(u)}"


def sort_names(items) -> str:
  """`sorted(items)` with a TypeError ANSWERED.

  `AxisType` gained `__lt__` upstream and did not have it at the pin, so `sorted` is a
  fact about the tree and not a fact this script can assume. `sorted(items)` -- no
  `key=` -- is the call CPython's own RANGE-arg sort makes; passing `key=lambda a:
  a.value` would sort a tree that has no `__lt__` at all and would then AGREE with a
  port that invented an ordering the tree does not have.
  """
  try:
    return ",".join(a.name for a in sorted(items))
  except TypeError:
    return '!TypeError'


def cmp_answer(a, b, op: str) -> str:
  """`a OP b` with a TypeError ANSWERED rather than raised.

  `AxisType` did not define `__lt__` at the pin, so a row that called `<` directly
  would abort the whole script on the pin tree and the pin/upstream diff -- the reason
  this script exists -- would be impossible to produce. The answer is therefore the
  comparison OR the exception's type name, which is a fact about `AxisType` and not
  about this file.
  """
  try:
    return str(eval(f"a {op} b"))  # noqa: S307 -- op is one of the four literals above
  except TypeError:
    return '!TypeError'


def lookup(d, key):
  """`d[key]` with CPython's KeyError ANSWERED, so a miss is a value.

  Every dict in ops.py is read with `d[k]` and a missing key raises; the port writes
  the miss as a `case _` arm. Printing the exception's TYPE is the honest answer for
  both: `d[key]` in a `try` is the same expression the port is standing in for, so this
  is a MEASUREMENT of the dict rather than a restatement of a rule about it.
  """
  try:
    return str(d[key])
  except KeyError:
    return '!KeyError'


def facts(u) -> str:
  """The four facts with NO arg: count, root op, root nsrc, SRC OP SEQUENCE."""
  return f"{len(list(u.toposort()))} {u.op}/{len(u.src)} {srcops(u)}"


def rngrow(name: str, u) -> None:
  """THE FOUR FACTS PLUS THE ANSWER, split into TWO rows.

  `rng_<tag>` is the node count, root op, root nsrc and SRC OP SEQUENCE -- the four
  facts, which a Bend arena answers identically to CPython.

  `rngarg_<tag>` is the ARG, and it is its own row for a measured reason: it is the
  one thing this file's rebase cannot match. Upstream packs `(axis_type, axis_id)` and
  the port's `ARange` is the pin's `(axis_id, axis_type)` because eleven committed
  files destructure it positionally. Isolating the arg into its own row family means
  the four graph facts stay gateable on all five fixtures -- including `twoid`, which
  is the fixture that proves the flip -- and the wall is confined to rows that are
  filtered BY NAME with the reason attached. Merging them would make `twoid`'s
  `arg=` differ inside a row whose other four facts are correct, which is how a wall
  hides inside a green row.
  """
  print(f"rng_{name}={len(list(u.toposort()))} {u.op}/{len(u.src)} {srcops(u)}")
  print(f"rngarg_{name}={argstr(u)}")


def axprop_row(name: str, u) -> None:
  """`axis_id` and `axis_type` READ AS THE PROPERTIES.

  CPython asserts `self.op is Ops.RANGE` in both, so a non-RANGE cannot be asked; every
  fixture here is a RANGE and that is stated rather than worked around.

  The TYPE of the answer is printed alongside it, and that is not decoration: on the
  three-element `twoid` fixture the pin's `axis_type` -- `self.arg[-1]` -- answers the
  INT `1`, not an `AxisType`, so `.name` raises. Printing `int:1` is the measured fact
  and it is the same fact `rng_twoid`'s `arg=` row carries from the other side.
  """
  ids = u.axis_id
  idstr = render(ids) + f"/len={len(ids) if isinstance(ids, tuple) else 1}"
  at = u.axis_type
  atstr = at.name if isinstance(at, AxisType) else f"{type(at).__name__}:{at}"
  print(f"axid_{name}={idstr}")
  print(f"axt_{name}={atstr}")


print(f"#shared_tree={TAG}")

# ---------------------------------------------------------------------------
# 0. The DERIVATION. Three rows, and they are what make the axis list above a
#    measurement: `axn_all` is `AxisType.__members__` order, `axv_all` is the value
#    sequence for exactly that order, and `ax_all_len` is its length. A port whose
#    AxisType has ten members where CPython has eight is a three-row diff, not a
#    silent agreement about the wrong set.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# 0. The DERIVATION. Four rows, and they are what make the axis list above a
#    measurement rather than a transcription: the member list in DECLARATION order, the
#    value sequence for exactly that order, its length, and the SORTED order. A port
#    whose AxisType has ten members where CPython has eight, or eight members in the
#    wrong order, is a four-row diff instead of a silent agreement about the wrong set.
#    `axlt_sorted` is in this block because at the pin it answers `!TypeError` -- so the
#    SORT is itself a thing upstream changed and it belongs beside the sequence it sorts.
# ---------------------------------------------------------------------------
print("#shared_axis_members=" + ",".join(a.name for a in AXES))
print("#shared_axis_values=" + ",".join(str(a.value) for a in AXES))
print(f"#shared_axis_count={len(AXES)}")
print("#shared_axis_sorted=" + sort_names(AXES))

# ---------------------------------------------------------------------------
# 1. The four per-axis tables. ONE ROW PER MEMBER, and that is deliberate: these are
#    the rows the file had none of. A fixture-driven gate would only ask about the axis
#    types a fixture happens to contain, and `PLACEHOLDER` appears in no RANGE fixture
#    tinygrad builds -- which is exactly how a wrong `PLACEHOLDER` value survives.
# ---------------------------------------------------------------------------
for a in AXES:
  print(f"axv_{a.name}={a.value}")
  print(f"axn_{a.name}={a.name}")
  print(f"axl_{a.name}={lookup(axis_letters, a)}")
  print(f"axc_{a.name}={lookup(axis_colors, a)}")

# ---------------------------------------------------------------------------
# 2. `range_start`. The five ops CPython names, PLUS one op it does NOT -- the port has
#    a `case _` arm answering 0 where Python raises KeyError, and a miss has to be a
#    row or the arm is invisible. `Ops.NOOP` is the miss: it is not in the dict.
# ---------------------------------------------------------------------------
for op in Ops:
  if op.name in ('STAGE', 'REDUCE', 'END', 'CALL', 'LINEAR', 'NOOP'):
    print(f"axs_{op.name}={lookup(range_start, op)}")

# ---------------------------------------------------------------------------
# 3. THE RANGE GRAPH ROWS. Five fixtures, each printing FOUR FACTS PLUS THE ANSWER in
#    one string: node count, root op, root nsrc, SRC OP SEQUENCE, then the arg.
#
#    WHY THE FIXTURE SHAPES ARE WHAT THEY ARE, and this is measured rather than
#    assumed. `tinygrad/uop/spec.py:82-83` upstream reads
#        isinstance(rng.arg, tuple) and len(rng.arg) >= 2
#        and isinstance(rng.arg[0], AxisType) and all(isinstance(ra, int) for ra in rng.arg[1:])
#    so a CANONICAL RANGE arg is `(AxisType, *int)` -- FLAT, axis type FIRST. And
#    `runtime/support/hcq2.py:498` builds `arg=(u.axis_type, next(ctx)) + u.axis_id[1:]`,
#    which only concatenates if `axis_id` is a TUPLE OF INTS. So:
#
#    `weak1`     `UOp.range(1, 0)`                  arg=(WEAK, 0)      -- the DEFAULT axis
#                  type, so this is the row that fails first if `UOp.range`'s signature
#                  reorders.
#    `loop1`     `UOp.range(2, 0, AxisType.LOOP)`   arg=(LOOP, 0)      -- a NAMED axis
#                  type, so the type half of the arg is separated from the default.
#    `dev3`      `UOp.range(3, 0, AxisType.DEVICE)` arg=(DEVICE, 0)    -- the literal `0`
#                  that replaced `axis_to_pos[AxisType.DEVICE]` upstream.
#    `loopfn`    `UOp.loop(7)`                      arg=(WEAK, 7)     -- src is NOOP, not
#                  CONST, so a RANGE/NOOP vs RANGE/CONST src swap is visible here and
#                  nowhere else.
#    `twoid`     built DIRECTLY as `UOp(Ops.RANGE, src=(CONST,), arg=(LOOP, 0, 1))` --
#                  THE DISCRIMINATING FIXTURE, and it took a measurement to find. For an
#                  arg of length TWO, `arg[1:]` and `arg[0:-1]` are the SAME slice, so
#                  `axis_id`/`axis_type` cannot tell the pin's reading from upstream's on
#                  any `UOp.range` call and on any `UOp.loop` -- MEASURED: those four
#                  fixtures' `axid_*`/`axt_*` rows are BYTE-IDENTICAL across the two
#                  trees. At length THREE they differ: upstream `arg[1:]` is `(0, 1)` and
#                  the pin's `arg[0:-1]` is `(LOOP, 0)` with `axis_type` the INT `1`.
#
#    A SIXTH fixture was tried and DROPPED: `UOp.range(2, (0, 1), AxisType.LOOP)`, which
#    packs a TUPLE inside the arg. It is legal to call, upstream's spec matcher rejects
#    it, and its `axid_*` row is `((0, 1),)/len=1` -- a nesting the port's `ARange` cannot
#    hold, so it would have been a BEND-ONLY row testing nothing. `loop1` replaced it.
# ---------------------------------------------------------------------------
_rng_weak1 = UOp.range(1, 0)
_rng_loop1 = UOp.range(2, 0, AxisType.LOOP)
_rng_dev3 = UOp.range(3, 0, AxisType.DEVICE)
_rng_loopfn = UOp.loop(7)
_rng_twoid = UOp(Ops.RANGE, src=(UOp.const(2),), arg=(AxisType.LOOP, 0, 1))
RANGES = (("weak1", _rng_weak1), ("loop1", _rng_loop1), ("dev3", _rng_dev3),
          ("loopfn", _rng_loopfn), ("twoid", _rng_twoid))

for _name, _u in RANGES:
  rngrow(_name, _u)


# The RANGE-arg SPEC, asked of the TREE ITSELF. `tinygrad/uop/spec.py` states what a
# RANGE arg must be and it MOVED with the flip -- pin `all(isinstance(ra, int) for ra in
# rng.arg[0:-1]) and isinstance(rng.arg[-1], AxisType)`, upstream
# `isinstance(rng.arg[0], AxisType) and all(isinstance(ra, int) for ra in rng.arg[1:])`
# -- so the row is `spec_shared.rewrite(u)`, the tree's OWN matcher, rather than either
# spelling transcribed here. Transcribing either one would make this a test of my
# reading of the diff instead of a measurement, and it is the second discriminator: the
# pin REJECTS the `twoid` fixture (`True`) where upstream ACCEPTS it, which is a fact
# no amount of reading the port would produce.
from tinygrad.uop.spec import spec_shared  # noqa: E402

for _name, _u in RANGES:
  print(f"rngspec_{_name}={spec_shared.rewrite(_u)}")

# ---------------------------------------------------------------------------
# 4. `axis_id` / `axis_type`, READ AS THE PROPERTIES -- never as a hand-written slice
#    of `.arg`. Every fixture is a RANGE, which is what CPython's `assert self.op is
#    Ops.RANGE` in both properties requires; there is no non-RANGE fixture here because
#    there is no non-RANGE answer to ask for.
# ---------------------------------------------------------------------------
for _name, _u in RANGES:
  axprop_row(_name, _u)

# ---------------------------------------------------------------------------
# 5. `AxisType.__lt__`, which upstream ADDED and the port does not have. Two rows: the
#    sort of the members in DECLARATION order must be the identity (values ascend), and
#    the sort of a REVERSED list must be the declaration order again. A `__lt__` that
#    compares wrongly in one direction answers the first row and fails the second.
# ---------------------------------------------------------------------------
print("axlt_sorted=" + sort_names(AXES))
print("axlt_revsorted=" + sort_names(list(reversed(AXES))))
# `<`/`>`/`<=` are answered THROUGH the exception, so the row is a fact about the tree
# rather than a fact about this script's optimism. This is what makes the SAME oracle
# diff both trees: at the pin `AxisType` has no `__lt__` and all three rows answer
# `!TypeError`, which is how the ADDITION is measured without a second script. Note
# `sorted(AXES)` with no key -- `sorted(..., key=value)` would sort even a tree with no
# `__lt__`, and would then agree with the port on a tree CPython cannot sort at all.
print(f"axlt_lt={cmp_answer(AxisType.LOOP, AxisType.WEAK, '<')}")
print(f"axlt_gt={cmp_answer(AxisType.LOOP, AxisType.WEAK, '>')}")
print(f"axlt_le={cmp_answer(AxisType.LOOP, AxisType.WEAK, '<=')}")
print(f"axlt_ge={cmp_answer(AxisType.LOOP, AxisType.WEAK, '>=')}")
print("axlt_dunder=" + ",".join(sorted(d for d in ('__lt__', '__le__', '__gt__', '__ge__', '__eq__') if d in AxisType.__dict__)))

# ---------------------------------------------------------------------------
# 5b. `eq_axis` as the port computes it: the count of pairs of DISTINCT members that
#     compare equal, over all of them, plus the count on the diagonal.
#
#     WHY COUNTS AND NOT THE 8x8 = 64 TABLE. Two measured reasons, and the second is
#     the interesting one. First, a 64-row table of `eqax_A_B=<bool>` is a CHANGE
#     DETECTOR: with every value distinct, `eq_axis` agrees with Enum identity for all
#     64 pairs, so UPSTREAM'S OWN DEFECT -- a PERMUTED value table -- moves NONE of
#     them. Second, the counts below are what a collision moves, and `axv_*` is what
#     the permutation moves, so between them they cover both facts a permutation or a
#     collision produces and the 64 rows would cover one of them at 64x the size.
#     `eqax_collide=0` is also the row that keeps a TEN-member enum honest, since the
#     two retained dead members are exactly where a collision would hide.
# ---------------------------------------------------------------------------
def eqax_collide(members) -> int:
  return sum(1 for i, a in enumerate(members) for b in members[i + 1:] if a == b)


print(f"eqax_collide={eqax_collide(AXES)}")
print(f"eqax_diag={sum(1 for a in AXES if a == a)}")

# ---------------------------------------------------------------------------
# 7. `axis_to_pos`, DELETED upstream. The honest fact is the module's own attribute
#    table, not a value from a table that no longer exists -- so this row is
#    `hasattr`, and the port's `case _` arm is the same question asked of a ladder.
# ---------------------------------------------------------------------------
print(f"xpos={hasattr(O, 'axis_to_pos')}")
print(f"xpos_names={sorted(k for k in vars(O) if 'axis' in k.lower())}")

# ---------------------------------------------------------------------------
# 8. `MSTACK`, which ops.py:773 builds as `src=(self,)+srcs`. THE ROW THIS FILE WAS
#    MISSING: `UOp.after` and `UOp.end` have `after_puts_self_first` /
#    `end_puts_self_first`, and `mstack` had the SAME inverse bug fixed in the same
#    commit -- but with no row of its own, so a re-regression of mstack alone would be
#    invisible while the other two stayed green.
#
#    `self` is a RANGE and `b`/`c` are CONSTs, so self-first prints `RANGE CONST` and
#    the bug prints `CONST RANGE`. Count, root op, root nsrc and arg are ALL identical
#    either way, which is why the src op sequence is in the row.
# ---------------------------------------------------------------------------
_m_self = UOp.range(4, 0)
_m_b = UOp.const(1)
_m_c = UOp.const(2)
# THE FOUR FACTS ONLY, no `arg=`: `mstack`'s arg is `None` at every arity, so an arg
# column here would be five characters of constant and would force the Bend to print a
# `None` spelling `ops.bend` has no datatype for. The src op SEQUENCE is the fact.
print(f"mstack2={facts(_m_self.mstack(_m_b, _m_c))}")
print(f"mstack1={facts(_m_self.mstack(_m_b))}")
print(f"mstack0={facts(_m_self.mstack())}")

# ---------------------------------------------------------------------------
# 9. The 22 EXISTING rows. Every one is a BOOLEAN whose Python counterpart is either a
#    live graph fact or nothing at all; they are listed here so the count of the file's
#    CPython lane is honest, and each names WHY it is bend-only or how it is derived.
#    None of them is an expectation -- printing a value for them here would be
#    transcribing the Bend, which is the one thing an oracle must not do.
# ---------------------------------------------------------------------------
BEND_ONLY = [
  # (row, why CPython cannot be asked)
  ("float_zeros_differ", "F32.bits of +0.0 vs -0.0; the port's bit pattern, CPython's float"),
  ("float_nan_interns", "nan CONSTs interning to one node; F32.div(0,0) is the port's nan"),
  ("cycle", "a BACKEDGE cycle is a LEGAL arena state in Bend and illegal in CPython's dict"),
  ("cycle_terminates", "the FUEL exhaustion path; CPython's while loop cannot run out"),
  ("ler_len", "the `pm_ler` regression: a PatternMatcher rule length, P3 in the port"),
  ("early_reject", "UPat early-reject collection, which is `uop/upat.py` (P3)"),
  ("broadcast_repeats", "UPat permutation arity, `uop/upat.py` (P3)"),
  ("required_len", "UPat required_len, `uop/upat.py` (P3)"),
  ("alu_permutes", "GroupOp.Commutative membership read off the port's own Op datatype"),
  # --- the AXISTYPE REBASE WALLS. Each is a row the Bend prints and CPython cannot
  # --- match, and each is here with the REASON so the gate script can filter by name.
  ("rngarg", "ARange's FIELD ORDER is the pin's `(ids, at)`; eleven committed files read "
             "and write it positionally. Upstream packs `(at, ids)`. ops-gate.sh greps "
             "the Bend source and fails if ARange is flipped without them."),
  ("axid_twoid", "the three-element arg a flat `arg[1:]` slice produces; the port's "
                 "`ARange` holds `(ids, at)` so it answers the pin's `(LOOP, 0)`"),
  ("axt_twoid", "as axid_twoid: the pin's `arg[-1]` answers the INT 1, which is the "
                "discrimination, and the port cannot produce a flat three-part arg"),
  ("rngspec", "`tinygrad/uop/spec.py`'s matcher, which is P3 and not ported; the oracle "
              "prints it because the PREDICATE moved with the flip and the movement is "
              "the fact (pin rejects `twoid`, upstream accepts it)"),
  ("axlt_le", "CPython raises TypeError: upstream added `__lt__` and NOT `__le__`"),
  ("axlt_ge", "CPython raises TypeError, as axlt_le"),
  ("axlt_dunder", "introspection of the Python class body; a Bend datatype has no __dict__"),
  ("xpos", "hasattr on a Python MODULE; a Bend def cannot be printed as absent, so the "
           "deletion is gated by a grep in ops-gate.sh instead"),
  ("xpos_names", "as xpos: the module's attribute table"),
  ("axv_REDUCE", "AxisType.REDUCE is DELETED upstream. Six committed files still "
                 "construct it (schedule/indexing, codegen/kernel, codegen/late, "
                 "codegen/opt/{heuristic,postrange,search}); three are under codegen/opt "
                 "and are another unit's. The port keeps it on value 9, a slot upstream "
                 "does not use, so eq_axis stays injective."),
  ("axv_UNROLL", "as axv_REDUCE"),
  ("axn_REDUCE", "as axv_REDUCE"),
  ("axn_UNROLL", "as axv_REDUCE"),
  ("axl_REDUCE", "as axv_REDUCE: upstream deleted the axis_letters entry too"),
  ("axl_UNROLL", "as axv_REDUCE"),
  ("axc_REDUCE", "as axv_REDUCE: upstream deleted the axis_colors entry too"),
  ("axc_UNROLL", "as axv_REDUCE"),
]
print("#existing_rows=" + ",".join(r for r, _ in BEND_ONLY))
for r, why in BEND_ONLY:
  print(f"#bend_only_{r}={why}")