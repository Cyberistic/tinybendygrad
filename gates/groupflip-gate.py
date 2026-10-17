#!/usr/bin/env python3
"""groupflip-gate.py -- `UOp.group` and `Tensor.flip` against CPython, AS UPSTREAM HAS THEM NOW.

    .venv/bin/python gates/groupflip-gate.py

ELEVEN ROWS, THREE LANES' WORTH OF CLAIM, AND ONE CLAIM ONLY: the port's TOPOSORT for the two
behaviours equals CPython's. Upstream deleted `Ops.GROUP` and `Ops.FLIP` (`900880433`, "remove
Ops.FLIP", 2026-10-11) and kept both behaviours -- `UOp.group` is now `UOp(Ops.STACK).after(...)`
at ops.py:536-538 and `Tensor.flip` is a PAD/SHRINK/TRANSPOSE loop at movement.py:233-267 -- so
the port's `tinybendygrad/uop/ops.bend` and `tinybendygrad/mixin/movement.bend` had to be
re-expressed over ops that still exist. This gate is what says whether they were.

WHY A TOPOSORT AND NOT A RETURN VALUE. The corpus (`checks/differ.py run`, 34 graphs) treats
the GRAPH as the contract: eleven of its graphs reach `group` and one has a dedicated `flip`
fixture, and after the enum deletion the eleven must reach `STACK` instead of losing a node.
A behaviour that is right but produces a different graph is not ported. Every row is therefore
the whole toposort in walk order -- `<OP>x<nsrc>[<src ops>]` per node, `|`-joined -- which
carries the ORDER, the op, the src COUNT and the src OP SEQUENCE. The last of those is the
only field that sees a two-src swap; `ops.bend`'s `after_puts_self_first` header records a swap
that left the count, the root op, the root nsrc and the toposort ALL identical.

THE POPULATION IS DISCOVERED FROM BOTH LANES, NOT LISTED TWICE. `ROWS` is the eleven names both
files print, and `_lane()` reads each lane's OWN artifact, so a row that one lane fails to emit
is a NAMED MISSING rather than a silent pass -- a gate that compares two dicts it built from
its own constant is a gate that cannot see a dropped row.

WHAT THIS GATE CANNOT SEE, NAMED.

  (a) THE CORPUS'S OWN DRIVER. `.agents/slop/graphcmp.py --side py` raises
      `AttributeError: 'ParamArg' object has no attribute 'size'` at its `paramarg` (:710)
      against the re-vendored `tinygrad/`: `HEAD:tinygrad` and `upstream:tinygrad` are both
      `62319c8ae612e51102916000d401d601a090353f` and upstream's `ParamArg` (ops.py:25-37) has
      no `size` member. MEASURED on all twelve of this file's graphs. So the corpus's CPython
      lane cannot be re-run at this tree, which is why this gate builds its own.
  (b) THE CORPUS'S BEND LANE TRANSCRIBES THE OLD CONSTRUCTION. `graphcmp.bend` mints
      `O.UOp.new(..., O.OpsGROUP{}, ...)` at twelve sites and never calls the port's
      `UOp.group`, so re-expressing `group` cannot move the corpus's toposort by itself: the
      fixture has to be re-pointed at the def, and `.agents/slop/` is outside every grant.
      `graphcmp-oracle.py` (the frozen `.py` lane) DOES call `UOp.group`, at nineteen sites.
  (c) THE `None` ARGUMENT. Upstream's `group` filters `None` and counts the UNFILTERED length,
      so `UOp.group(None, a)` is `AFTER(STACK, a)` upstream and `a` on the port, whose
      parameter is `List<&2, U32>` with no spelling for an absent element. The port cannot print
      upstream's answer, so it is not a row; `groupflip-oracle.py` writes it to STDERR as
      `gap_none_filter=` so the gap is a number in the transcript.
  (d) `_resolve_dim` AND THE `dedup` REFUSAL. `movement.py:249` resolves negative axes and
      `:251` raises on a repeated one; neither is ported, for the reasons `mixin/movement.bend`'s
      new flip header names. `flip_10` therefore exercises the ORDER and not the refusal.
  (e) **THE AXIS, AND THAT IS A LIMIT OF THE BASE AND NOT OF THE ROW FORMAT ALONE.**
      `mxw_reshape(mxw_base(), [4,4,4,4])` has `shape[0] == shape[axis]` on every axis, and
      `movement.py:257-259` reads `crop`/`tail` from `x.shape[1:]` with `x = ret.transpose(0,
      axis)` (`:256`) -- the shape minus the AXIS dim -- where a port reading
      `mxw_dims_of(ret)[1:]` drops dim 0 and keeps dim `axis`. The two lists agree iff
      `shape[0] == shape[axis]`, so on a cube of 4s the defect is the IDENTITY and these eleven
      rows cannot see it. MEASURED: the wrong `crop` moved `mxw_flip`'s result shape on
      `mxw_base()` and on (2,4,4,8) while leaving every row of THIS gate byte-identical.
      `gates/axisflip-gate.py` is the gate that carries the shape, on (2,4,4,8), and its `axis1`
      row is that gate's own blindness guard. It was green for the wrong reason on a blind base
      until the shape rows existed; this gate is green on an order claim, which is a real one, but
      it is not a claim that `flip` gets the axis right.
"""

import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import BEND, PY, Gate, gate

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

# THE ELEVEN ROWS, in the driver's own order: five `UOp.group` arms then six `Tensor.flip`
# shapes. `gatekit` refuses the run if a lane disagrees with this count, so the count is a
# MEASUREMENT of the lanes and not a typed inventory.
ROWS = ("group0", "group1", "group2", "group3", "group6",
        "flip_none", "flip_0", "flip_1", "flip_01", "flip_10", "flip_3")

# ZERO DECLARED DIVERGENCES, and the file says so rather than leaving the number implicit: the
# eleven rows are all COMPARED rows. The three gaps that exist are named in the header above and
# NONE of them is a row -- (c) is a gap the port cannot print, (a) and (b) are about the
# corpus's driver rather than about these two behaviours. A pins file with zero entries would
# be a file whose population is empty and whose only content is a header; this comment is the
# same statement without the file.
DIVERGING = ()


def _lane(name):
  """`(row -> value)` for one lane's own artifact, or `{}` when it is absent.

  It reads the lane's OWN output rather than a second derivation that could drift from it, and
  it treats a MISSING row as a missing row: `gatekit`'s row count is checked against `ROWS`, so
  a lane that dropped one fails the count instead of quietly agreeing on the other ten.
  """
  out = {}
  for ext in (".cmp", ".rows", ".out"):
    f = HERE / "artifacts" / "groupflip-gate" / f"{name}{ext}"
    if f.is_file():
      out.update({l.split("=", 1)[0]: l.split("=", 1)[1]
                  for l in f.read_text().splitlines() if "=" in l})
  return out


def port_has_no_group_node() -> bool:
  """NO ROW OF THE PORT'S TOPOSORT NAMES `Ops.GROUP`, AND NO ROW NAMES `Ops.FLIP` EITHER.

  This is the claim the whole task turns on -- "they do not lose a node, they reach a DIFFERENT
  op" -- stated so it can fail. It is read from the port lane's own rows rather than from the
  diff, because a diff that agreed would not notice an op name it agreed about: the eleven rows
  comparing equal to CPython is the witness, and THIS is the witness that the ops are `STACK`
  and `AFTER` and not the two deleted members. It is falsifiable in the other direction too --
  a port that minted `OpsGROUP` again, with CPython minting it too, would agree on every row and
  go green here, and that is exactly the state this tree must not reach.
  """
  port = _lane("bd")
  missing = [r for r in ROWS if r not in port]
  if missing:
    print(f"port_has_no_group_node: {missing} is missing from the port lane")
    return False
  for r in ROWS:
    for gone in ("Ops.GROUP", "Ops.FLIP"):
      if gone in port[r]:
        print(f"port_has_no_group_node: row {r} still names {gone} -- upstream deleted the member "
              "at 900880433 and the port's `UOp.group` must reach STACK/AFTER instead")
        return False
  hit = [r for r in ROWS if "Ops.STACK" in port[r] or "Ops.AFTER" in port[r]]
  if not hit:
    print("port_has_no_group_node: no row reaches Ops.STACK or Ops.AFTER, so the claim that the "
          "GROUP arms moved to STACK/AFTER is untested -- a port that deleted the behaviours "
          "would satisfy every other row of this gate")
    return False
  print(f"port_has_no_group_node: no row names Ops.GROUP or Ops.FLIP and {len(hit)} of {len(ROWS)} "
        f"rows reach Ops.STACK or Ops.AFTER ({hit})")
  return True


GATE = Gate(
  "groupflip-gate",
  bend="groupflip.bend",
  oracle="groupflip-oracle.py",
  rows=len(ROWS),
  compared=len(ROWS) - len(DIVERGING),
  diverges={},
  pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)


def main() -> int:
  return gate(GATE,
              f"groupflip-gate: PASS -- {len(ROWS)} rows compared exactly, 0 declared divergences; "
              "the witness is the TOPOSORT for `UOp.group` (ops.py:536-538) and `Tensor.flip` "
              "(movement.py:233-267)",
              checks=port_has_no_group_node)


if __name__ == "__main__":
  sys.exit(main())