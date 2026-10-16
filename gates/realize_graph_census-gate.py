#!/usr/bin/env python3
"""realize_graph_census-gate.py -- A GRAPH CENSUS over
`tinybendygrad/engine/realize.bend`, the port of `tinygrad/engine/realize.py`.

    .venv/bin/python gates/realize_graph_census-gate.py
    .venv/bin/python gates/realize_graph_census-gate.py --refresh   # rewrites the pins file

1004 ROWS (15 DRIVERS x 65 NODES + 15 BOTTOM + 12 ARM-COVERAGE + 2 HEADER), THREE LANES,
940 EXACT MATCHES AND 64 DECLARED DIVERGENCES -- 9 CLASSES, AND 1 FINDING STANDING.
OF THE 1004 ROWS ONLY 611 CARRY A COMPARISON: 378 are `notacall` (nine CALL-only drivers
x 42 non-CALL nodes) and 15 are the `Arena.bottom()` slot CPython has no node for. BOTH
KINDS ARE INSIDE THE MATCHES, because both lanes answer them identically, and a verdict line
that printed the match count as a comparison count would be claiming things this gate did
not do. `compares_holds()` measures the refusal population off the lanes on every run and
`ret_is_uop_fixed_holds()` is the same discipline for the eight rows `ret is not uop`
repaired.

`realize.py` is 297 lines and the port is 281 defs, and `realize.bend` ships its own
50-row `main` (realize.bend:2099) whose expectations were read out of a live CPython run.
What was ungated was the ANSWER against CPython'S: nothing compared a port reader to the
function it ports, so a reader that returned the wrong list agreed with itself. This is
that lane, and it found two things.

THE POPULATION IS THE (DRIVER, NODE) PRODUCT, AND BOTH AXES ARE DISCOVERED. A ROW is a
pair. NODE ranges over `realize.bend`'s own `main_arena` (its 42 slots, index for index)
PLUS the twenty-three nodes `gates/realize_graph_census.bend` chains onto it, each named in
that file by the dispatch arm it exists for: `main_arena` has no MSELECT, no GETADDR, no
MSTACK, no SHRINK, no SINK without a `KernelInfo`, no PROGRAM whose kernel is unnamed and
no MSELECT in an `outs` slot, so `rz_arm`'s MSELECT/SHRINK/MSTACK arms, HEAD's GETADDR
arm, `gcc_sink`'s and `gcc_pick.prog`'s DEFAULT arms, `gn_body`'s default arm and
`get_call_written_bufs`'s MSELECT wall would ALL have been unreachable rows -- and it has
no MULTI-DEVICE buffer either, so `len()` would have been tested only on lists of length 0
and 1. DRIVER ranges over FIFTEEN, and `drivers_hold()` re-derives the set on every run:

  (a) the eight entry points whose `(fuel: Nat, )?+ar: O.Arena` signature INTERSECTS the
      names `realize.py` itself defines -- MEASURED by `re.findall` over the file and
      `dir(tinygrad.engine.realize)`: `get_call_arg_uops`, `resolve_params`,
      `get_call_outs_ins`, `get_call_written_bufs`, `get_call_kernels`, `get_call_name`,
      `get_call_var_uops`, `_get_call_to_compile`;
  (b) the three more that own a `case O.Ops*` arm with NO name in `realize.py` --
      `rz_est_of`, `rz_nbytes_of` (`estimate_uop`) and `has_dnum` (`unwrap_multi:139`);
  (c) the three `*_table` defs -- `grep -c '^def [a-z]*_table' tinybendygrad/engine/realize.bend`
      = 3, and they are `flatten_table`, `validate_table`, `beam_table`.

EVERY PAIR IS EMITTED, refusals included, so the two lanes carry the same row count BY
CONSTRUCTION: a lane that filtered its own refusals would let a disagreement about WHICH
pairs fire hide inside the filter. `rows` is PRINTED by both lanes and is 1004.

THE DRIVER AXIS IS DECLARED IN FOUR PLACES AND **ALL FOUR ARE READ BACK**, by `axis_hold()`.
It used to be declared in EIGHT and NONE of them was read back: the gate's own `DRV` was
checked against a second fifteen-name literal written beside it, the oracle wrote its order
out twice in its `__main__` plus once per arm in `drive`, and the bend lane wrote it three
more times (`rs_drv_name`, `rs_d.go`, `rs_call_only`). Only the oracle's `CALL_ONLY` was
LOADED BY PATH. `grep -c 'drv ==\\|rs_drv_name' gates/realize_graph_census-gate.py` measured
**0**. So the axis is now: the oracle's one `DRIVERS` tuple (loaded by path), the oracle's
`drive` ladder, and the bend lane's three `match` tables, each read with a regex over its
OWN write site and compared for content, order, dense indexing and distinct callees.

THE CALL-ONLY RULE IS CPYTHON'S, APPLIED ON BOTH SIDES. `UOp.body` (ops.py:562) RAISES
for a non-CALL and nine of realize's readers read `call.body` or `call.src[1]`, so those
rows have no CPython answer. Both lanes answer the literal `notacall` there, decided by
the node's OWN op tag -- a fixture fact, not a list -- and 369 of the rows are that.

THE ORACLE CALLS THE REAL THING, and it cost two defects to get there.
`gates/tn_bitwise_not-oracle.py`'s docstring is the post-mortem for an oracle that
hand-built `cast.ne(true_)` instead of calling `Tensor.bitwise_not()`, so driver and
oracle both minted the CAST CPython folds. `gates/decomp_graph_census-oracle.py` records
it a SECOND time, in `f2f`'s fixture dtype. It happened HERE TWICE MORE and both are
recorded in the oracle's own header: `_add` returned the SLOT instead of the NODE, so
every CALL carried the integers `11, 2, 3` as its `src` and all eighteen answered
`AttributeError: 'int' object has no attribute 'is_bound_var'`; and `KernelInfo(nm, (),
None, beam)` POSITIONALLY put the beam into `estimates` -- `KernelInfo` is FIVE fields
(ops.py:1342-1347) and the port carries FOUR -- so `pm_beam`'s `sink.arg.beam == 0` guard
fired on a sink carrying beam 2 and `beam_24` read as a PORT divergence on a graph the
two sides agreed about node for node.

`tinygrad/engine/realize.py` HAS DRIFTED SINCE THE PIN `ad117c928^`. MEASURED:
`git diff --stat 'ad117c928^' HEAD -- tinygrad/engine/realize.py` is `15 insertions(+),
14 deletions(-)`; the working-tree blob is `16d0d413a494153a794cf4033992909563c44c50`,
which equals `git rev-parse 'ad117c928:tinygrad/engine/realize.py'` and NOT the pin's
`54610743bfa50c532cf87b27cfedf596087a994d`. `AGENTS.md` says `ad117c928^` IS the pin and
`ad117c928` is this project's own re-vendor, so FOR A DRIFTED FILE THE PIN IS THE
TRUTHFUL ORACLE AND HEAD IS NOT. The ONE piece of that drift which touches a ported arm is
`_resolve`'s `Ops.GETADDR`, and it is FINDING 1. See the block at the foot.

THE TWO FINDINGS THIS CENSUS FOUND. FINDING 2 IS FIXED; FINDING 1 IS NOT, AND IT IS NOT
A DEFECT IN THE PORT -- it is a vendored-drift row and it is pinned as a divergence so
that it stays visible.

  FINDING 1 -- `res_63`, `_resolve` HAS NO `OpsGETADDR` ARM. `rz_arm` reads
  `OpsMSELECT OpsSHRINK OpsBITCAST OpsMSTACK OpsPARAM` and HEAD's `realize.py:129`
  is `if b.op in (Ops.MSELECT, Ops.SHRINK, Ops.BITCAST, Ops.GETADDR)`. MEASURED on the
  `vv` call, whose second argument is a GETADDR over a PARAM: CPython answers
  `BUFFER/1+GETADDR/1<-BUFFER/1` (the GETADDR's `src[0]` went through `inputs[slot]`) and
  the port answers `BUFFER/1+GETADDR/1<-PARAM/0`. **UNDER THE PIN THE ARM DOES NOT EXIST**
  -- `git show 'ad117c928^:tinygrad/engine/realize.py'` line 129 reads
  `if b.op in (Ops.MSELECT, Ops.SHRINK, Ops.BITCAST):` -- so the port is CORRECT against
  the pin and INCOMPLETE against HEAD, and the pin is where the row agrees. THIS ROW IS
  NOT CANNOT-BE-SEEN: it took a GETADDR OVER A PARAM to see it, because HEAD's `_resolve`
  recurses into `src[0]` and a BUFFER comes back unchanged, so a GETADDR over a BUFFER
  rewrites to a CONTENT-IDENTICAL node that hash-conses. MEASURED: with only a GETADDR
  over a BUFFER in the fixture, `res_51` AGREED on both sides. It also took
  `inputs = (b1, b0)` rather than `(g1, g0)`, because both `g0` and `g1` are `PARAM/0` and
  a slot lookup of either prints `PARAM/0` -- MEASURED, with PARAM inputs `res_63` ALSO
  agreed. Two printer decisions stood between the instrument and the finding, and
  `realize.bend`'s own `res_slot0`/`res_slot1` rows would have missed both.

  FINDING 2 -- the eight `bea0_*` rows, `pm_beam` HAS NO `ret is not uop`. `ops.py:1618`
  is `if (ret:=match(uop, ctx)) is not None and ret is not uop: return ret`, so an answer
  that IS THE NODE ITSELF is dropped. `pm_beam`'s body is
  `call.replace(src=(sink.replace(arg=replace(sink.arg, beam=ctx)), *call.src[1:]))`,
  and at `ctx == 0` on a SINK that already carries `beam = 0` every replacement is the
  identity, so `UOp.new` hash-conses and the answer IS the input node. MEASURED,
  `bea0` at `ctx=0` on the `l` call: CPython answered `0` and the port answered
  `1:CALL/2,SINK/0,PARAM/0:b=0`. FIXED -- `bm_new` ends with `M.hop_self`, which IS that
  clause, and `RET_IS_UOP_FIXED` names the eight rows `classes_hold` still holds at `0`.
  `beam_0` WAS THE SAME DEFECT AT A DIFFERENT ctx AND IS NOT COUNTED TWICE: at `ctx=7` the
  rewrite really changes the node and the two sides agree on the cone AND on the beam,
  which is why `ret_is_uop_fixed_holds()` insists some ctx-7 row still carries `b=7` --
  a fix that dropped every rewrite would pass the ctx-0 check alone.

THE 65 DIVERGENCES, CLASSIFIED, PINNED ON BOTH SIDES, AND EVERY CLASS MEASURED.

  0 `SRC_BODY` -- FIXED. `realize.py:15`'s `call.src[1:]` is UNCONDITIONAL and the port
      used `O.Arena.src_without_body`, which is `src[1:]` FOR A CALL AND `src` FOR
      EVERYTHING ELSE, so a non-CALL gained `src[0]` at the head: 52 rows over 26 of the
      41 non-CALLs, on both readers that walk the list. The fix is
      `O.Arena.src_from(ar, call, 1)` in `get_call_arg_uops` AND in `rz_bound_map`
      (`realize.py:18` is the same slice), and `SRC_BODY_FIXED` asserts all 52 still agree.
      **AND ONLY THE FIRST OF THOSE TWO SITES IS COVERED BY ANY OF THE 52: MEASURED,
      reverting `get_call_arg_uops` moves exactly 52 rows and reverting `rz_bound_map`
      moves ZERO.** The cause is not that the second fix is unnecessary -- `realize.py:18`
      is the same slice and the port's own comment at the class says every caller passes a
      CALL, so the two spellings agree wherever the port is RUN. It is that no row can
      reach them: `get_call_var_uops` is driven by `var`, which is CALL-only on BOTH lanes
      because `u.body` raises for a non-CALL, and for a CALL `src_from(ar, call, 1)` and
      `Arena.src_without_body` ARE the same value. So the second site is a FAITHFULNESS fix
      with no row behind it, and saying otherwise would be a row count doing a proof's job.
      Closing it needs a node whose `src[0]` is a BOUND VAR (a bare CONST is dropped by
      `is_bound_var` either way, which is why `b0`/`b1` over `CONST 3` cannot witness it)
      AND a driver that passes `prg` explicitly -- `realize.py`'s own signature takes it, so
      that driver is honest; it is recorded in the commit and NOT done here.

  15 `BOTTOM` -- `Arena.empty` spends slot 0 on `bottom()` and CPython has no such node,
      so there is nothing to compare and the row says `bottom`. `no_bottom_value` says the
      port never answers a VALUE there, which is the shape a stale-arena self-loop takes.

  13 `NAME_ARM` -- `get_call_name` (realize.py:43). The port implements the PROGRAM and
      `encdec` arms; the STORE arm needs a device NAME (`Device.tag` is P6,
      `uop/spec.bend:1488` -- AND THAT CITATION IS WRONG ABOUT THIS TREE, see
      `kern_blind_holds`) and the fallthrough is a `raise`, which the port spells `none`.
      Eleven rows are the `NotImplementedError`, one is `name_18`, whose STORE arm reaches
      `bufs[0]` on the census's `bufs=[]` and raises `IndexError`, and one is `name_57`,
      whose PROGRAM's `src[0]` is a SINK with `arg=None` and CPython raises
      `AttributeError`. `encdec`'s ANSI-coloured string is FIXED and was the ONE row here
      that was NOT a wall -- see the block at the foot of this file.

  12 `VARS_BODY` -- `get_call_var_uops` (realize.py:16) reads `prg.arg.vars`, which is a
      `ProgramInfo` field; over a SINK or a `CustomFunction` body CPython raises
      `AttributeError` and the port's `rz_pvars.go` (realize.bend:507) answers `Nil{}`.

  10 `VAL_BODY` -- `pm_validate`'s BODY is not ported. `validate_table()` is read by
       `t_va_len` and by the census driver's tag-0 arm alone, and `_validate`'s
       `UOp.new_buffer` is a P6 device call while its `store_call` is `TODO(p3)` with
       `param_like` absent (ops.bend:5170-5171), so the port has a CLAIM and no graph and
       this lane compares a claim against a cone. Eight rows are that, `val_50`/`val_53`
       are CPython raising inside `_validate`. THE ELEVENTH WAS A DEAD DEF AND IS NOW
       FIXED: `val_27` is `pm_validate`'s TAG 1, which is `pm_flatten_linear` carried in
       by `PatternMatcher.__add__` -- `PatternMatcher(self.patterns+more.patterns)`
       (ops.py:1611) -- so `pm_validate.rewrite` tries it on the same node whenever tag 0
       does not claim. The census driver asked tag 0's claim ALONE and answered `0` where
       CPython answered the flatten cone; MEASURED, CPython's `val_27` and `flat_27` are
       BYTE-IDENTICAL, so the two lanes already agreed on that cone at the `flat` driver.
       The body was already in the port: the driver reaches `fl_0` through `rs_d_flat`,
       because a `Verdict` cannot print a cone. It does NOT go through `va_1`, and THAT IS
       A SEPARATE FINDING -- `va_1` and `va_0` are dead defs called by nothing (MEASURED:
       replacing `va_1`'s body with `VSkip` moves ZERO of the 1004 rows). The fix is a
       DISPATCH in the driver, not a new body.

  8 `ARG_SLOT` -- a CALL whose `src[1]` is NOT a PARAM or a BUFFER. `gcc_53` is a SINK
      (`c.device` is `None`, so `c.device[0]` raises `TypeError`), `gcc_50`/`gcc_60` are
      MSELECT and GETADDR (`Device[c.device]` asserts), `kern_53` is a SINK (CPython's
      `to_tuple(call.src[1].device)` answers one device and the port's `PArg.of` reads no
      `ParamArg`, so it answers NONE), `nb_53` is `prod(shape)` on a SINK, `est_57` is a
      PROGRAM whose `src[0].arg` is `None`, and `beam_55`/`bea0_55` are a SINK with no
      `KernelInfo`, where CPython raises `AttributeError` on `sink.arg.beam` and the port's
      `rz_kernel_beam` (realize.bend:1265) DEFAULTS IT TO ZERO. Every one of these is out
      of context: `realize.py` only ever puts a PARAM or a BUFFER in a CALL's argument
      slot, and none of them is reachable from a real graph. `rz_kernel_beam`'s default is
      the one with a wrong ANSWER rather than a missing one -- it makes a bodyless SINK
      fire `pm_beam` -- and it is pinned separately as `SINK_NO_KI` inside this class.

  2 `SLOT_MISS` -- `res_20` and `res_22`. `_resolve` ends `inputs[b.arg.slot]` with no
      default and CPython raises `IndexError`; the port's `rz_res.at` (realize.bend:1066)
      is `Maybe.default(..., b)`, a default CPython does not have. That default is RIGHT
      for `get_call_var_uops`'s `bound.get(v.expr, v)` and WRONG here -- the two readers
      share one helper and only one of them defaults. Safe direction: the argument points
      at the node the caller already had.

  1 `MSELECT_WALL` -- `wbuf_60`. `realize.py:32` resolves an MSELECT argument through
      `b.src[0].storage_base` and CPython answers `BUFFER/1@0`; the port's own header
      records `storage_base` as a wall (`ops.py:798`) and the `O.OpsBUFFER` test drops it.

  1 `MSTACK_WALL` -- `res_52`. `_resolve`'s `Ops.MSTACK` arm resolves EVERY src, and
      `rz_arm` answers an MSTACK unchanged: the walk and `_resolve` are mutual recursion
      and Bend refuses the two shapes tried (realize.bend:958-980 records both, and
      corrects the reason). NOT FIXED, and not fixable inside this unit: the fix is a
      worklist record plus an MSTACK node in `main_arena`.

  1 `GETADDR_DRIFT` is FINDING 1 above. `ret is not uop` IS FINDING 2 AND IT IS FIXED:
      the eight `bea0_*` rows agree on `10` and `RET_IS_UOP_FIXED` names them.

WHAT IT ASSERTS THAT NEEDS NO CPYTHON. `no_bottom_value`: neither port lane answers a
VALUE at slot 0, which is what `Arena.bottom()` being read as a real node would look like.
`arms_all_reached`: all twelve arm-coverage rows are non-zero, so every op tag realize's
dispatchers name has a fixture node that reaches it. `drivers_hold`: the driver axis is
still the measured intersection. **`axis_hold`: THE DRIVER AXIS IS READ BACK OUT OF FOUR
DECLARATIONS** -- the oracle's `DRIVERS` loaded by path, the oracle's `drive` ladder, and
the bend lane's own `rs_drv_name` and `rs_d.go` -- so a driver that exists on one side only
is a red run rather than a population only the driver can see. `calls_hold`: the 23 CALL
nodes are the ones both lanes refused to drive the CALL-only drivers on.
`compares_holds`: the refusal population is the whole `CALL_ONLY x NONCALL` product and
neither lane refused alone. `kern_blind_holds`: the fixture's multi-device answer really is
a list of TWO DISTINCT devices on BOTH lanes and `kern_65` really is `2` -- which is the
precondition under which `rs_d_kern`'s COUNT is worth comparing at all, and the measure of
what is left blind when it is (an ORDER SWAP inside `Dn{[6, 0]}`, because the port has no
device vocabulary to be wrong in: `Device.tag` does not exist in this tree's CPython and
`device.bend:344`'s `tag_of` is a three-valued sentinel). It says so out loud rather than
in a comment.

EXIT STATUS: 0 all three lanes identical after the pins and every class check holds ·
1 a lane took the wrong row count, the oracle failed, the native compile failed, the lanes
disagree, a pin moved, or a class check failed · 3 a precondition was absent (the pins
file, the output directory, the substrate, or the oracle).
"""

import hashlib
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import BEND, PY, Gate, REFUSED, gate
from tinygrad.uop.ops import Ops

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PINS = HERE / "realize_graph_census-pins.rows"
ART = HERE / "artifacts" / "realize_graph_census-gate"
PORT = ROOT / "tinybendygrad" / "engine" / "realize.bend"

# THE FIFTEEN DRIVERS, in the ORACLE'S ORDER -- `gatekit` diffs the lanes LINE BY LINE, so
# the order is part of the contract and it is the order the oracle prints. IT IS NO LONGER
# THE ONLY COPY: `axis_hold()` reads the oracle's `DRIVERS` BY PATH and the bend lane's own
# three dispatch tables back out of the driver, and holds all four equal. It used to be
# checked against a LITERAL of its own fifteen names here, which is the shape
# `checks/sweep.py`'s `LIVE_UNITS` had: a list nothing reads back, so a driver added on
# one side and not the other was invisible to the instrument.
DRV = ("arg", "nb", "res", "flat", "val", "beam", "bea0", "oi", "wbuf", "kern",
       "name", "est", "var", "gcc", "dnum")
NODES = 65

# THE 23 CALL NODES, MEASURED: `oi_<n> == "notacall"` on BOTH lanes iff `n` is not one of
# these, and `calls_hold()` re-derives it from the promoted lanes on every run. It is the
# fixture's own index map, read off `main_arena`'s comment (realize.bend:1485-1507) plus
# the twenty-three nodes the census adds, and it is written down so the class tuples below
# can be comprehensions rather than 125 literals.
CALLS = (17, 18, 19, 20, 21, 22, 23, 24, 25, 31, 35, 40, 49, 50, 51, 52,
         53, 55, 57, 60, 61, 63, 65)
NONCALL = tuple(n for n in range(1, NODES + 1) if n not in CALLS)

# THE CLASSIFICATION, HAND-DECLARED, AND EVERY NUMBER IN IT MEASURED. This tuple set IS
# the divergence POPULATION -- it is written here, in git, and the pins file is checked
# against it in BOTH directions, so neither can drift alone.
BOTTOM = tuple("b_" + d for d in DRV)
# `SRC_BODY` IS FIXED AND THIS CLASS IS THE EMPTY SET THAT SAYS SO, so `SRC_BODY_FIXED`
# holds the FIFTY-TWO ROW NAMES and `classes_hold` asserts every one of them still
# AGREES -- the shape `RET_IS_UOP_FIXED` already uses, and NOT the shape
# `--refresh` destroys: the row NAMES live in the gate, the prose lives in `_header()`,
# and neither is written by a run.
#
# WHAT IT WAS. `realize.py:15` is `tuple(s for s in call.src[1:] if not s.is_bound_var)`
# -- an UNCONDITIONAL slice -- and the port's `get_call_arg_uops` was
# `O.Arena.src_without_body`, which is `src[1:]` FOR A CALL AND `src` FOR EVERYTHING
# ELSE (`ops.bend:1407`, and it IS `UOp.src_without_body`, `ops.py:1327`). So over any
# non-CALL the port answered one EXTRA entry -- `src[0]` itself, at the HEAD -- and 26
# of the 41 non-CALL nodes diverged on each of the two readers that walk the list,
# `arg` and `res`. MEASURED: 52 rows of the 974 AT THE TIME (the census is 1004 now);
# 30 of the 82 candidate pairs agreed
# anyway (a 1-src non-CALL, or an `src[0]` the bound-var filter drops).
#
# THE FIX IS ONE CALL IN EACH OF TWO SITES: `O.Arena.src_from(ar, call, 1)` -- which is
# the same slice `rz_res`'s view rebuild (realize.bend:993) and `pm_beam`'s rebuild
# (realize.bend:1245) already call, so no new computation was written. Every caller of
# `get_call_arg_uops`/`rz_bound_map` in the port passes a CALL, so the two spellings
# agreed everywhere the port is RUN and the bug was reachable only from a driver that
# asks the function what it does to a node CPython never hands it.
#
# WAS THE "SAFE DIRECTION" CLAIM SAFE? Yes, and it was the wrong thing to leave alone:
# it argued the extra entries could not HARM a reachable graph, which is true and says
# nothing about being right. Matching realize.py:15 exactly is strictly better, costs two
# characters, and removes 52 pins rather than annotating them.
SRC_BODY_FIXED = (
    "arg_9", "arg_10", "arg_11", "arg_12", "arg_13", "arg_14", "arg_15", "arg_16",
    "arg_26", "arg_27", "arg_28", "arg_29", "arg_30", "arg_33", "arg_34", "arg_36",
    "arg_39", "arg_41", "arg_45", "arg_46", "arg_47", "arg_48", "arg_56", "arg_58",
    "arg_59", "arg_62",
    "res_9", "res_10", "res_11", "res_12", "res_13", "res_14", "res_15", "res_16",
    "res_26", "res_27", "res_28", "res_29", "res_30", "res_33", "res_34", "res_36",
    "res_39", "res_41", "res_45", "res_46", "res_47", "res_48", "res_56", "res_58",
    "res_59", "res_62",
)
SRC_BODY: tuple = ()
NAME_ARM = ("name_18", "name_21", "name_23", "name_24", "name_49", "name_50",
            "name_51", "name_52", "name_53", "name_55", "name_57", "name_61", "name_63")
VARS_BODY = ("var_21", "var_22", "var_23", "var_24", "var_49", "var_50", "var_51",
             "var_52", "var_53", "var_55", "var_61", "var_63")
VAL_BODY = ("val_23", "val_24", "val_49", "val_50", "val_51", "val_52",
            "val_53", "val_55", "val_61", "val_63")
ARG_SLOT = ("nb_53", "kern_53", "est_57", "gcc_50", "gcc_53", "gcc_60",
            "beam_55", "bea0_55")
# `rz_kernel_beam` DEFAULTS A `KernelInfo`-LESS SINK TO ZERO, so `pm_beam` FIRES on one
# where CPython raises. That is a wrong ANSWER inside `ARG_SLOT` rather than a refusal,
# and it is named separately so the class check can hold both claims apart.
SINK_NO_KI = ("beam_55", "bea0_55")
SLOT_MISS = ("res_20", "res_22")
MSELECT_WALL = ("wbuf_60",)
MSTACK_WALL = ("res_52",)
GETADDR_DRIFT = ("res_63",)
# FINDING 2 IS FIXED AND THIS CLASS IS THE EMPTY SET THAT SAYS SO. `pm_beam` had no
# `ret is not uop`, so at `ctx == 0` it answered the node it was handed; `bm_new` now ends
# with `M.hop_self` (`tinybendygrad/engine/realize.bend`, the clause `ops.py:1618` spells),
# the eight `bea0_*` rows AGREE, and the tuple is kept as the assertion that they STAY
# agreed -- MEASURED, with it still populated the gate went RED naming `bea0_23`, so the
# empty tuple is not a deletion nobody can check. `bea0_55` is NOT here and never was: it is
# `SINK_NO_KI` inside `ARG_SLOT`, because CPython raises `AttributeError` on a SINK with no
# `KernelInfo` while the port's `rz_kernel_beam` DEFAULTS its beam to 0.
RET_IS_UOP: tuple = ()
RET_IS_UOP_FIXED = ("bea0_23", "bea0_49", "bea0_50", "bea0_51", "bea0_52", "bea0_53",
                    "bea0_61", "bea0_63")

DIVERGING = (BOTTOM + SRC_BODY + NAME_ARM + VARS_BODY + VAL_BODY + ARG_SLOT +
             SLOT_MISS + MSELECT_WALL + MSTACK_WALL + GETADDR_DRIFT + RET_IS_UOP)
ROWS = (2 + len(BOTTOM) + 12 + len(DRV) * NODES,)


def _pins():
    """`(DIVERGES, why)` -- the pins LOADED BY PATH, and the population they must agree with.

    The content comes from the file, the POPULATION comes from the tuples above, and the
    two are checked against each other here rather than one being derived from the other: a
    row pinned and not declared is a pin nothing will ever exclude, and a row declared and
    not pinned is an exclusion with no content behind it. Both are failures here.
    """
    if not PINS.is_file():
        return None, (f"{PINS.name} is MISSING -- a gate's declared divergences must live in "
                      f"git, not in its own output directory")
    pins = {}
    for ln in PINS.read_text().splitlines():
        if not ln.strip() or ln.startswith("#"):
            continue
        row, py, bd = ln.split("\t")
        pins[row] = (py, bd)
    if set(pins) != set(DIVERGING):
        extra, gone = sorted(set(pins) - set(DIVERGING)), sorted(set(DIVERGING) - set(pins))
        return None, (f"the pins file and the declared classes disagree: pinned but not "
                      f"declared {extra}, declared but not pinned {gone}")
    return pins, ""


DIVERGES, WHY = _pins()


def _header(n_div, n_same):
    return f"""# realize_graph_census-pins.rows -- GENERATED by
# `realize_graph_census-gate.py --refresh`, which is its ONLY writer. One TAB-separated
# triple per declared divergence: `<row>\\t<CPython's LINE>\\t<the port's LINE>`, i.e. the
# expected content on BOTH sides, each WITH its own `row=` PREFIX because `gatekit`'s pin
# check is `want not in raw[lane]` -- a LIST-MEMBERSHIP test, so a bare value would never be
# found. MEASURED: with the values alone the first run answered `py's arg_10 is not 'none'`.
#
# {n_div} DIVERGENCES, {n_same} OF THE {ROWS[0]} ROWS AGREE EXACTLY. It is git-resident and
# beside the gate because `AGENTS.md`'s own rule is that a gate's required inputs live in
# git and not in `gates/artifacts/`: `gatekit` EMPTIES that directory before it runs and
# UNLINKS what it staged when the run was not green, so a divergence list read from there
# is destroyed by the first red run and there is then nothing left to edit.
#
# EACH COMMENT CARRIES ITS OWN SHA-256 PREFIX AND BYTE COUNT, so a reviewer sees a moved pin
# without reading a long line. A pin somebody TYPED wrong makes the gate RED; a pin read
# back out of the last run's own output cannot be wrong, which is the only argument for
# reading it from there and the reason for not doing so.
#
# THIS HEADER IS THE ONLY PLACE A RETIRED CLASS'S STORY SURVIVES `--refresh`. `--refresh`
# rewrites every `#` line it emits from the LIVE lanes, so a class that empties leaves
# behind a pins file that never mentions it and a `--refresh` is the ONLY writer. THAT
# HAS DESTROYED PROSE IN THIS TREE TWICE. SO THE TWO STORIES ARE HERE, IN THE FUNCTION
# THAT WRITES THE HEADER, AND THEIR ROW NAMES ARE IN THE GATE.
#
#   `RET_IS_UOP` -- EIGHT ROWS, NOW AGREE. `pm_beam` had no `ret is not uop`
#     (`ops.py:1618`), so at `ctx == 0` over a SINK that already carries `beam = 0` every
#     replacement in realize.py:218 is the identity, `UOp.new` hash-conses, and the answer
#     IS the input node. The fix is `M.hop_self` inside `bm_new`, at the BODY rather than
#     around the table. `RET_IS_UOP_FIXED` names the eight and `classes_hold` asserts both
#     lanes still answer `0` at ctx 0 while the ctx-7 rows still carry `b=7`.
#
#   `SRC_BODY` -- FIFTY-TWO ROWS, NOW AGREE. `realize.py:15`'s `call.src[1:]` is
#     UNCONDITIONAL and the port used `O.Arena.src_without_body`, which is `src[1:]` FOR A
#     CALL AND `src` FOR EVERYTHING ELSE, so a non-CALL gained `src[0]` at the HEAD. The
#     fix is `O.Arena.src_from(ar, call, 1)` in `get_call_arg_uops` AND in `rz_bound_map`
#     (realize.py:18 is the same slice). `SRC_BODY_FIXED` names the fifty-two and
#     `classes_hold` asserts `cpy[r] == port[r]` on each.
#
#   `VAL_BODY`'s ELEVENTH ROW, `val_27` -- NOW AGREE, and it was NOT A BODY AT ALL.
#     `pm_validate` is `PatternMatcher([...]) + pm_flatten_linear` (realize.py:214) and
#     `PatternMatcher.__add__` is `PatternMatcher(self.patterns+more.patterns)` (ops.py:1611),
#     so tag 1 is the flatten rule and `rewrite` tries it on the same node whenever tag 0
#     does not claim. The census driver asked tag 0's CLAIM alone and answered `0`, while
#     CPython answered the flatten cone. MEASURED: CPython's `val_27` and `flat_27` are
#     BYTE-IDENTICAL, so both lanes already agreed on that cone at the `flat` driver --
#     the body was already in the port -- the driver reaches `fl_0` through `rs_d_flat`,
#     because a `Verdict` cannot print a cone. The fix is a two-arm `match` in
#     `rs_d_val`, NOT a new body. IT DOES NOT REVIVE `va_1`: `va_1` and `va_0` are dead
#     defs called by nothing, and that is its own zero-row finding (MEASURED -- replacing
#     `va_1`'s body with `VSkip` moves ZERO of the 1004 rows and the gate stays GREEN).
#
#   `NAME_ARM`'s ONE ROW WITH A VALUE, `name_22` -- NOW AGREE, AND THE RECORDED REASON
#     FOR LEAVING IT WAS WRONG. The pin said the `encdec` arm "needs `sym_infer`, which is
#     `exec` of GENERATED SOURCE (ops.py:1177 -- `_sym_fxn`)". It does not: `sym_infer` is
#     `uop.sym_infer(vv) if isinstance(uop, UOp) else uop` (ops.py:93), and
#     `prod(shape) * dtype.itemsize` is an INT for a concrete shape, so the `else` branch
#     runs and no symbolic machinery is reached. MEASURED on this very node: shape `(16,)`,
#     dtype `i32`, product `64`, `sym_infer(64, {{}}) == 64`. What the arm needed was
#     `size_to_str` and `colored`, BOTH ALREADY PORTED (`helpers.bend:1143`, `:1083`), plus
#     `rz_nbytes`, which was in `realize.bend` and already answers `None` for a SYMBOLIC
#     dim -- and CPython's `sym_infer` on a symbolic node with `var_vals or {{}}` = `{{}}`
#     raises `NameError`, so that `None` is the faithful absence. EIGHTH instance in this
#     tree of a correct def that was present and unread, and the WRONG REASON is the
#     finding: it had been quoted forward from `realize.bend`'s own header, which is how a
#     wall becomes a fact without anyone measuring it.
"""


def refresh() -> int:
    """REWRITE `realize_graph_census-pins.rows` from a fresh pair of lanes. Its only writer.

    It does NOT go through `Gate.run()`, because a refresh is exactly what a run cannot do
    when the pins are wrong: the whole point is to replace them. Both lanes are produced
    here and the divergence rows are whatever DISAGREES, so the population is a measurement
    of the pair -- and the header, the per-row class comment and the byte counts are
    rewritten with it, because a pins file whose prose outlives its content is a second
    document disagreeing with the first.
    """
    py = subprocess.run([str(PY), str(HERE / "realize_graph_census-oracle.py")],
                        capture_output=True, text=True, cwd=ROOT)
    bd = subprocess.run([str(BEND), "gates/realize_graph_census.bend"],
                        capture_output=True, text=True, cwd=ROOT)
    if py.returncode or bd.returncode:
        print(f"--refresh: a lane failed (py rc={py.returncode}, bd rc={bd.returncode}); "
              f"nothing written", file=sys.stderr)
        return 1
    got = {t: dict(l.split("=", 1) for l in s.splitlines() if "=" in l)
           for t, s in (("py", py.stdout), ("bd", bd.stdout))}
    rows = sorted(k for k in got["bd"] if got["py"].get(k) != got["bd"].get(k))
    cls = {}
    for r in DIVERGING:
        cls[r] = next((n for n, grp in (("BOTTOM", BOTTOM), ("SRC_BODY", SRC_BODY),
                                        ("NAME_ARM", NAME_ARM), ("VARS_BODY", VARS_BODY),
                                        ("VAL_BODY", VAL_BODY), ("ARG_SLOT", ARG_SLOT),
                                        ("SLOT_MISS", SLOT_MISS),
                                        ("MSELECT_WALL", MSELECT_WALL),
                                        ("MSTACK_WALL", MSTACK_WALL),
                                        ("GETADDR_DRIFT", GETADDR_DRIFT),
                                        ("RET_IS_UOP", RET_IS_UOP)) if r in grp), "?")
    out = [_header(len(rows), len(got["bd"]) - len(rows))]
    for r in rows:
        if cls[r] == "?":
            print(f"--refresh: {r} DIVERGES and no class declares it; a divergence with no "
                  f"class is a pins row nothing will ever explain. Nothing written",
                  file=sys.stderr)
            return 1
        py_line, bd_line = "%s=%s" % (r, got["py"][r]), "%s=%s" % (r, got["bd"][r])
        out.append("# %-13s %-40s cpy %6d B %s | port %6d B %s" % (
            r, cls[r], len(py_line), hashlib.sha256(py_line.encode()).hexdigest()[:12],
            len(bd_line), hashlib.sha256(bd_line.encode()).hexdigest()[:12]))
        out.append("%s\t%s\t%s" % (r, py_line, bd_line))
    PINS.write_text("\n".join(out) + "\n")
    print(f"--refresh: {PINS.name} rewritten -- {len(rows)} divergences, "
          f"{len(got['bd']) - len(rows)} exact matches")
    return 0


def _lane(name):
    f = ART / name
    if not f.is_file():
        return None
    return dict(l.split("=", 1) for l in f.read_text().splitlines() if "=" in l)


def classes_hold() -> bool:
    """EVERY CLASS'S MEASURED CLAIM, CHECKED ON THE LANES THIS RUN JUST PROMOTED.

    The pins already make a moved row RED; this says WHY each row is allowed to differ, in
    the terms the class is defined by, so a divergence that keeps its text cannot silently
    change what it is. A gate that only pins differences is a gate that has forgotten what
    it is pinning.
    """
    port, cpy = _lane("bd.out"), _lane("py.rows")
    if port is None or cpy is None:
        print("  classes_hold: the promoted lanes are not there")
        return False
    ok = True

    def bad(msg):
        nonlocal ok
        print("  " + msg)
        ok = False

    # SRC_BODY, NOW FIXED: the fifty-two rows it used to name must AGREE. The pin already
    # freezes CPython's value, so `cpy[r] == port[r]` is the claim that the port still
    # answers it -- a port that went back to `Arena.src_without_body` would answer one
    # entry longer and this is the row that says so by name rather than by a diff.
    for r in SRC_BODY_FIXED:
        if cpy[r] != port[r]:
            bad(f"{r}: cpy={cpy[r]!r} port={port[r]!r}, and the 52 `src[1:]` rows must "
                f"still AGREE -- `get_call_arg_uops` is `O.Arena.src_from(ar, call, 1)`")
    # BOTTOM: the port answers something, and it is NEVER a value it read off the arena.
    for r in BOTTOM:
        if port[r] == "bottom":
            bad(f"{r}: the port agrees with a node CPython does not have")
    # NAME_ARM / VARS_BODY: the port answers `none` where CPython cannot answer at all.
    for r in NAME_ARM + VARS_BODY:
        if port[r] != "none":
            bad(f"{r}: the port answers {port[r]!r}, not `none`")
    # VAL_BODY: the port has the CLAIM and no body, so its answer is the claim's bit.
    for r in VAL_BODY:
        if port[r] not in ("0", "1"):
            bad(f"{r}: the port answers {port[r]!r}, which is neither claim bit")
    # ARG_SLOT: a CALL whose `src[1]` is not a PARAM or a BUFFER. `kern_53` is the one that
    # ANSWERS a different COUNT rather than a refusal, and it is held separately.
    for r in ARG_SLOT:
        if not cpy[r].startswith("raise=") and r != "kern_53":
            bad(f"{r}: cpy {cpy[r]!r} is not a raise, so it is not in this class")
    if (cpy["kern_53"], port["kern_53"]) != ("1", "0"):
        bad(f"kern_53: cpy={cpy['kern_53']!r} port={port['kern_53']!r}, "
            f"not the declared SINK-in-the-arg-slot pair")
    # SINK_NO_KI: CPython RAISES `AttributeError` on `sink.arg.beam` for a SINK with no
    # `KernelInfo`, and the port's `rz_kernel_beam` DEFAULTS it to 0 -- so the rule CLAIMS
    # the node where CPython cannot run it at all. BOTH CONTEXTS NOW ANSWER `10`, i.e.
    # "claimed, and the rewrite was the identity", and that is `rz_beam_sink.go`'s `_` arm
    # (its own header's reason) leaving a bodyless SINK alone: the CALL `bm_new` rebuilds is
    # CONTENT-IDENTICAL to `CALL(54, 2)` -- node 55 itself -- and hash-conses to it, so
    # `M.hop_self` answers index 0. **AND THE CLAIM BIT IS WHY `rz_kernel_beam`'s DEFAULT IS
    # A ROW AT ALL:** with the old one-bit printer the claim was folded away and mutating
    # the default `0` -> `1` moved zero of the rows -- `V2`, reported as vacuous and now
    # moving these two. With two bits, a default of 1 answers `00` here and is caught.
    for r in SINK_NO_KI:
        if cpy[r] != "raise=AttributeError" or port[r] != "10":
            bad(f"{r}: cpy={cpy[r]!r} port={port[r]!r}, not the declared SINK_NO_KI pair")
    # SLOT_MISS: CPython raises IndexError on `inputs[slot]` and the port defaults to the
    # node, so the port's answer CONTAINS the node CPython refused to look up.
    for r in SLOT_MISS:
        if cpy[r] != "raise=IndexError" or port[r] == "none":
            bad(f"{r}: cpy={cpy[r]!r} port={port[r]!r}, not the declared SLOT_MISS pair")
    # MSELECT_WALL: CPython resolves the MSELECT to its storage base and the port drops it.
    if (cpy["wbuf_60"], port["wbuf_60"]) != ("BUFFER/1@0", "none"):
        bad(f"wbuf_60: cpy={cpy['wbuf_60']!r} port={port['wbuf_60']!r}, "
            f"not the declared MSELECT wall")
    # GETADDR_DRIFT, THE VENDORED-DRIFT FINDING: the SAME node with the SAME op and arity,
    # differing only in what `src[0]` BECAME -- and the `@<slot>` suffix is what says WHICH
    # input it became, which `BUFFER/1` alone could not. One more level is the instrument.
    if (cpy["res_63"], port["res_63"]) != ("BUFFER/1@0+GETADDR/1<-BUFFER/1@1+CONST(1)",
                                           "BUFFER/1@0+GETADDR/1<-PARAM/0@0+CONST(1)"):
        bad(f"res_63: cpy={cpy['res_63']!r} port={port['res_63']!r}, "
            f"not the declared GETADDR drift pair")
    # RET_IS_UOP, NOW FIXED: at ctx 0 both lanes answer `10` -- CLAIMED and the rewrite was
    # the identity -- and the ctx-7 rows answer the same CONE **and the same BEAM**.
    # `ret_is_uop_fixed_holds()` is the separate claim; this is the guard that the fix did
    # not move the OTHER context.
    for r in RET_IS_UOP_FIXED:
        if cpy[r] != "10" or port[r] != "10":
            bad(f"{r}: cpy={cpy[r]!r} port={port[r]!r}, and the ctx-0 row must be '10' "
                f"(claimed, identity rewrite) on BOTH sides now that `bm_new` carries "
                f"`M.hop_self`")
    return ok


def ret_is_uop_fixed_holds() -> bool:
    """FINDING 2 IS FIXED, AND THIS IS THE ROW THAT WOULD CATCH A REGRESSION.

    `pm_beam`'s clause is CONTEXT-DEPENDENT, so a fix that made ctx 7 disagree would be a
    regression and not a fix. The census drives `beam` at ctx 7 and `bea0` at ctx 0 for
    exactly that reason, and this check holds both halves: the eight ctx-0 rows answer
    `10` on the lanes -- CLAIMED, and the rewrite was the identity, which is what the clause
    drops -- and the ctx-7 rows still carry `b=7` and still begin `11`. A `M.hop_self` that
    dropped too eagerly would make them `00` or `b=0`, and both are caught here.

    THE `00` ROWS ARE ALSO HELD, and that is new: a fix that stopped CLAIMING would make
    the eight `10`s into `00`s and `ret_is_uop_fixed_holds` would see it, but a fix that
    claimed EVERY node would leave the eight `10`s alone and turn the fifty-odd `00`s into
    `10`s. So the check is that the population has BOTH.
    """
    ok = True
    for lane in ("bd.out", "bn.out"):
        rows = _lane(lane)
        if rows is None:
            print(f"  ret_is_uop_fixed_holds: {lane} is not there")
            return False
        for r in RET_IS_UOP_FIXED:
            if rows[r] != "10":
                print(f"  ret_is_uop_fixed_holds: {lane} {r}={rows[r]!r}, "
                      f"the `ret is not uop` clause is not firing at ctx 0")
                ok = False
        sig = [rows[r] for r in rows if r.startswith(("beam_", "bea0_"))]
        fired = [v for v in sig if v.startswith("11")]
        skipped = [v for v in sig if v == "00"]
        if not fired:
            print(f"  ret_is_uop_fixed_holds: {lane} has NO ctx-7 row that fired -- "
                  f"a fix that dropped every rewrite would pass the ctx-0 check alone")
            ok = False
        if not skipped:
            print(f"  ret_is_uop_fixed_holds: {lane} has NO row the rule refused, so a "
                  f"claim that fires on everything would pass the ctx-0 check alone")
            ok = False
        for r in rows:
            if rows[r].startswith("11") and not rows[r].endswith(":b=7"):
                print(f"  ret_is_uop_fixed_holds: {lane} {r}={rows[r]!r} does not carry "
                      f"b=7 -- the ctx-7 rewrite moved")
                ok = False
    return ok


def no_bottom_value() -> bool:
    """SLOT 0 IS `Arena.bottom()` AND A PORT LANE THAT ANSWERED A VALUE THERE WOULD BE
    READING THE BOTTOM AS A NODE.

    This is the stale-arena self-loop in its cheapest form, and `decomp_graph_census`'s
    `no_noop_bottom` is the same assertion for `NOOP`. Checked off BOTH PORT LANES' own
    output and not re-derived: the property is about what the port PRINTED. The twelve
    arm-coverage rows are checked here too, because a tag with no node is an arm no row can
    reach and a census that cannot see its own population cannot be wrong.

    THE ACCEPTED ANSWERS AT SLOT 0 ARE NAMED, because the beam printer made this a
    two-bit verdict and a list of three strings would have gone red on `b_beam=00` for a
    reason that is not a defect. `00` and `10` are CLAIM VERDICTS -- "the rule did not
    claim" and "it claimed and the rewrite was the identity" -- and neither carries a node.
    `01` and `11` DO carry a cone, so a stale arena or a body that ran on a refused node
    would print one and land here.
    """
    no_value = ("none", "notacall", "0", "00", "10")
    for lane in ("bd.out", "bn.out"):
        f = ART / lane
        if not f.is_file():
            return False
        rows = _lane(lane)
        for r in BOTTOM:
            if rows.get(r, "bottom") not in no_value:
                print(f"  {lane}: {r}={rows.get(r)!r} reads the BOTTOM as a node")
                return False
        for k, v in rows.items():
            if k.startswith("arm_") and v == "0":
                print(f"  {lane}: {k}=0 -- an op tag with no fixture node reaches no arm")
                return False
    return True


def drivers_hold() -> bool:
    """THE DRIVER AXIS IS THE MEASURED INTERSECTION, RE-DERIVED FROM THE FILE AND THE
    MODULE, NOT FROM THIS FILE'S WORD FOR IT.

    (a) every def of `realize.bend` whose first parameter is `+ar: O.Arena` (or
    `fuel: Nat, +ar: O.Arena`), INTERSECTED with the names `realize.py` itself defines;
    (b) the defs that own a `case O.Ops*` arm with no such name -- `rz_est_of`,
    `rz_nbytes_of`, `has_dnum`;
    (c) the `*_table` defs.

    (a) and (c) are computed here, from the two live sources. If `realize.py` grows a
    public reader, or `realize.bend` grows a table, this gate goes RED before the census
    has said a word about it -- which is the whole argument for a discovered population
    over a hand list.
    """
    import tinygrad.engine.realize as RZ
    src = PORT.read_text()
    got = set(re.findall(r"^def ([a-z_0-9]+)\((?:fuel: Nat, )?\+ar: O\.Arena", src, re.M))
    inter = {n for n in dir(RZ) if not n.startswith("__")} & got
    tables = set(re.findall(r"^def ([a-z_0-9]+)_table\(", src, re.M))
    # THE NINE LADDERS, FOUND BY TAKING THE ENCLOSING `^def` OF EVERY `case O.Ops*` -- the
    # parameter-name regex misses four of them because `op` is not always the first
    # parameter, so the arms are located by where they ARE, not by a signature.
    lines = src.split("\n")
    arms, cases = set(), 0
    for i, ln in enumerate(lines):
        if re.match(r"\s*case O\.Ops[A-Z]", ln):
            cases += 1
            for j in range(i, -1, -1):
                if lines[j].startswith("def "):
                    arms.add(lines[j][4:].split("(")[0])
                    break
    ok = True
    if len(inter) != 8:
        print(f"  drivers_hold: (a) is {len(inter)} entry points, the file declares 8")
        ok = False
    if len(tables) != 3:
        print(f"  drivers_hold: (c) is {len(tables)} *_table defs, the file declares 3")
        ok = False
    if len(arms) != 9:
        print(f"  drivers_hold: {len(arms)} ladders own a `case O.Ops*` arm, "
              f"the file declares 9: {sorted(arms)}")
        ok = False
    # FIFTEEN UNTIL `get_call_name` GREW ITS `encdec` ARM, AND THEN IT IS SIXTEEN. `gn_prog`
    # became `gn_body` -- so the LADDER count above is still 9 and `gn_body` is not a new
    # driver -- and it went from two arms to three, because `realize.py:50` dispatches
    # `encdec` on its own and folding it into the `_` arm would be a computed-value match,
    # which Bend refuses. This is the port's dispatch surface growing by one and the gate
    # following it, NOT a threshold relaxed to let a change through.
    if cases != 16:
        print(f"  drivers_hold: `case O.Ops*` is {cases} arms, the file declares 16")
        ok = False
    # (a)'s EIGHT names and (c)'s THREE table drivers are named in the file under the
    # census's OWN short spelling, so the check is membership -- and the membership half no
    # longer compares against a LITERAL written here, because that was the whole of the
    # Box-2 finding: a fifteen-name tuple compared with a second fifteen-name tuple is a
    # population only this file can see. `axis_hold()` reads the oracle's `DRIVERS` by path
    # and the bend lane's own three dispatch tables out of the driver and holds all four
    # equal, so the axis is DISCOVERED from four sites rather than asserted from one.
    if len(DRV) != 15:
        print(f"  drivers_hold: the declared driver axis is {len(DRV)} drivers, "
              f"the verdict line says 15")
        ok = False
    # (a)'s eight REALIZE.PY names are driven under the census's OWN short spelling, so the
    # check is that the MAPPING is total -- a name `realize.py` owns and the axis cannot
    # spell is a driver the census is missing, and saying so beats a hard-coded list.
    SHORT = {"get_call_arg_uops": "arg", "resolve_params": "res", "get_call_outs_ins": "oi",
             "get_call_written_bufs": "wbuf", "get_call_kernels": "kern",
             "get_call_name": "name", "get_call_var_uops": "var",
             "_get_call_to_compile": "gcc", "estimate_uop": "est",
             "unwrap_multi": "nb"}
    miss = sorted({SHORT[n] for n in inter if n in SHORT} - set(DRV))
    if miss:
        print(f"  drivers_hold: (a) names map to {miss}, which the axis does not drive")
        ok = False
    unowned = sorted(n for n in inter if n not in SHORT)
    if unowned:
        print(f"  drivers_hold: (a) has no short name for {unowned} -- a new realize.py "
              f"reader would go ungated")
        ok = False
    return ok


def _code(src: str) -> str:
    """THE SOURCE WITH ITS COMMENTS REMOVED, quote-aware, and that is the whole reason
    this exists.

    EVERY SHAPE THIS FILE MATCHES IS ALSO QUOTED IN ITS OWN PROSE. The driver explains what
    `rs_duo` mints by printing `S.Dn{[6, 0]}` in the comment above it, and the first
    version of `kern_blind_holds` counted that comment as a SECOND device -- MEASURED: it
    answered 2 where the fixture mints one -- and took the gate RED on a correct tree. An
    instrument that cannot tell code from prose about its own population is
    `checks/differ.py`'s `ORACLE_WORD` basename-regex defect (`670 of 675` files classified
    by FILENAME) one level down, and the fix is the same one: parse the code.

    `#` INSIDE A STRING IS NOT A COMMENT, so the scan tracks the open quote rather than
    splitting on the first `#`. MEASURED with `tokenize` over the oracle: **0** string
    literals contain `#`, and the `.bend` driver's own literals are `":b="`, `"b_"`,
    `"b_"`+name and the op tags, none of which carries one -- so the tracker is what keeps
    that from being a rule about this file.
    """
    out = []
    for ln in src.splitlines():
        quote, cut = None, None
        for i, ch in enumerate(ln):
            if quote is not None:
                if ch == quote:
                    quote = None
            elif ch in "\"'":
                quote = ch
            elif ch == "#":
                cut = i
                break
        out.append(ln if cut is None else ln[:cut])
    return "\n".join(out)


def _bend_arms(src: str, defname: str) -> tuple[list[str], list[int | None], bool]:
    """`def <name>`'s `case` arms as `(bodies, indices, dense)`, IN SOURCE ORDER.

    A `match` is the only place a bend driver can declare an axis -- there is no table to
    read -- so a REGEX OVER THE TREE'S OWN WRITE SITE is the discovery mechanism, and it is
    the third of the three shapes `AGENTS.md`'s doctrine 1 admits: "a REGEX OVER THE TREE'S
    OWN WRITE SITES, with the list admitted in a comment and a ledger so the edit is
    visible". The three write sites read here are named in `axis_hold`'s docstring; a fourth
    hand-written copy of the axis is not a population and `axis_hold` says so.

    THE `_` ARM IS THE LAST INDEX and comes back as `None`, so `dense` is True only when
    the explicit indices are a `0..n-1` ramp AND the `_` arm, if there is one, is the LAST
    one -- which is what makes a RENAMED or REORDERED arm visible rather than merely
    absent. MEASURED before this was written: all three of these tables spell fourteen of
    their fifteen arms and leave the fifteenth to `case _:`, so a parser that required
    `0..14` would have taken the gate red for nothing.

    The scan is bounded by the NEXT top-level `def`, because `rs_d.go`'s last arm is a
    `case _:` and a greedy scan would swallow `rs_d`'s own arms.
    """
    start = src.find(f"\ndef {defname}(")
    if start < 0:
        return [], [], False
    end = src.find("\ndef ", start + 1)
    body = src[start:end if end > 0 else len(src)]
    arms = re.findall(r"^\s*case (\d+|_):\s*(.*)$", body, re.M)
    idx = [None if n == "_" else int(n) for n, _ in arms]
    explicit = [i for i in idx if i is not None]
    dense = (explicit == list(range(len(explicit)))
             and idx.count(None) <= 1
             and (None not in idx or idx[-1] is None))
    return [v.strip() for _, v in arms], idx, dense


def axis_hold() -> bool:
    """THE DRIVER AXIS, READ BACK FROM FOUR PLACES, NONE OF THEM A LITERAL HERE.

    **BOX 2.** The axis used to be written out in eight places and this gate read NONE of
    them: `grep -c 'drv ==\\|rs_drv_name' gates/realize_graph_census-gate.py` was **0**,
    `drivers_hold`'s membership half was `set(DRV)` against a literal fifteen names written
    two hundred lines away, and only the oracle's `CALL_ONLY` was loaded by path. A
    population declared once and never read back is a population only the driver can see --
    the `REALIZEGAPS` finding, which is the same class as `checks/sweep.py`'s `LIVE_UNITS`.

    The four sites, and where each is read from:
      1 the oracle's `DRIVERS` tuple, LOADED BY PATH through `_load_oracle()`;
      2 the oracle's `drive` ladder -- the `if drv == "..."` arms, one per driver;
      3 the bend lane's `rs_drv_name` -- the `U32 -> name` table the row KEYS are built from,
        compared IN ORDER against the oracle's, because arm `N` names the driver at index
        `N` and `gatekit` diffs the lanes line by line;
      4 the bend lane's `rs_d.go` -- the `U32 -> driver` dispatch, held to the same order.
        A distinct-callee claim was WRITTEN, MEASURED and REMOVED: `beam` and `bea0`
        dispatch to the same body at two contexts, which is the whole reason `bea0` exists.
    Plus a fifth, checked because it is the axis's OTHER attribute: the bend lane's
    `rs_call_only` table against the oracle's `CALL_ONLY`.

    WHAT IT CANNOT SEE: a name that is wrong in all four places at once, because then the
    four agree. That is not this check's failure -- it is the same agreement a passing diff
    has -- and `classes_hold`/`calls_hold`/`compares_holds` are what hold the CONTENT.
    """
    ok = True
    try:
        oracle = _load_oracle()
    except Exception as e:                                   # noqa: BLE001
        print(f"  axis_hold: the oracle module would not load: {e}")
        return False
    src = _code((HERE / "realize_graph_census.bend").read_text())

    def bad(msg):
        nonlocal ok
        print("  axis_hold: " + msg)
        ok = False

    # (1) the oracle's declared order, LOADED BY PATH.
    got_oracle = tuple(oracle.DRIVERS)
    if got_oracle != DRV:
        bad(f"the oracle's DRIVERS is {list(got_oracle)}, the gate's DRV is {list(DRV)}")
    # (2) the oracle's ladder: one `if drv == "<name>"` per driver. **AS A SET AND NOT IN
    #     ORDER**, and the measurement for that is `drive`'s own arm order
    #     -- arg, var, oi, wbuf, kern, name, est, gcc, dnum, nb, res, flat, val, beam, bea0
    #     -- which is neither `DRIVERS`' order nor alphabetical: it is the order the ladder
    #     was written in, and a `drive` dispatch does not care. `DRIVERS` IS ordered,
    #     because `gatekit` diffs the lanes LINE BY LINE, so THAT is where the order is
    #     checked and it is checked against the bend lane's indexed tables below. What the
    #     ladder must have is exactly one arm per driver: a driver with none answers
    #     `raise=NoDriver` and one with two answers the first.
    ladder = re.findall(r'if drv == "([a-z0-9]+)":',
                        _code((HERE / "realize_graph_census-oracle.py").read_text()))
    if sorted(ladder) != sorted(got_oracle) or len(set(ladder)) != len(ladder):
        bad(f"the oracle's `drive` ladder holds {ladder} and its DRIVERS is "
            f"{list(got_oracle)}")
    # (3) the bend lane's name table -- the `U32 -> name` map every row KEY is built from,
    #     `rs_put(String.concat([rs_drv_name(d), "_", ...]))`. A dense ramp matters as much
    #     as the names: a gap names two rows from one arm.
    names, idx, dense = _bend_arms(src, "rs_drv_name")
    if not dense:
        bad(f"`rs_drv_name`'s arms are indexed {idx} and the row keys are built from them")
    if [b.strip('"') for b in names] != list(got_oracle):
        bad(f"`rs_drv_name` is {[b.strip(chr(34)) for b in names]} and the oracle's DRIVERS "
            f"is {list(got_oracle)} -- IN THAT ORDER, because the row keys are printed in "
            f"the driver's index order and `gatekit` diffs line by line")
    # (4) the bend lane's dispatch. **NO DISTINCT-CALLEE CLAIM, AND THAT IS MEASURED:**
    #     `beam` and `bea0` dispatch to the SAME body at two contexts
    #     (`rs_d_beam(ar, n, 7)` / `rs_d_beam(ar, n, 0)`), which is the entire reason `bea0`
    #     exists -- the `ret is not uop` clause is context-dependent, so it needs a second
    #     row over the same table. A distinct-callee check would have gone red on the gate's
    #     own design, and a guard that cannot fire on a correct tree is a guard that cannot
    #     be trusted when it does. What IS checked is the ORDER, because arm `N` is the
    #     driver whose name is arm `N` of `rs_drv_name`.
    callees, idx, dense = _bend_arms(src, "rs_d.go")
    if not dense:
        bad(f"`rs_d.go`'s arms are indexed {idx}")
    if len(callees) != len(got_oracle):
        bad(f"`rs_d.go` has {len(callees)} arms and the axis has {len(got_oracle)} drivers")
    # (5) the axis's OTHER ATTRIBUTE: `rs_call_only`'s `True{}` arms against the oracle's
    #     `CALL_ONLY`. The `_` arm is the last driver, so index `len-1` is its verdict.
    bodies, idx, dense = _bend_arms(src, "rs_call_only")
    if not dense or len(bodies) != len(got_oracle):
        bad(f"`rs_call_only` has {len(bodies)} arms indexed {idx} and the axis has "
            f"{len(got_oracle)} drivers")
    else:
        port_only = {i for i, b in enumerate(bodies) if b.startswith("True{}")}
        want_only = {i for i, d in enumerate(got_oracle) if d in oracle.CALL_ONLY}
        if port_only != want_only:
            bad(f"`rs_call_only` refuses indices {sorted(port_only)} and the oracle's "
                f"CALL_ONLY is {sorted(oracle.CALL_ONLY)}, i.e. {sorted(want_only)}")
    if len({len(DRV), len(got_oracle), len(callees), len(names)}) != 1:
        bad(f"the four sites hold {len(DRV)}, {len(got_oracle)}, {len(callees)} and "
            f"{len(names)} drivers")
    return ok


def _load_oracle():
    """THE ORACLE AS A MODULE, BY PATH. Its file name carries a HYPHEN, so its module name
    is not derivable from it: MEASURED, `import realize_graph_census_oracle` answers
    `ModuleNotFoundError` even with `gates/` on the path. It is loaded ONCE and cached in
    `sys.modules`, because a second load rebuilds the fixture and `B` would be a different
    list of nodes from the one the lanes were driven on.
    """
    name = "realize_graph_census_oracle"
    if name not in sys.modules:
        import importlib.util
        spec = importlib.util.spec_from_file_location(name, HERE / "realize_graph_census-oracle.py")
        mod = importlib.util.module_from_spec(spec)
        sys.modules[name] = mod
        spec.loader.exec_module(mod)
    return sys.modules[name]


def pin_drift_holds() -> bool:
    """THE VENDORED-DRIFT CHECK, RUN AND NOT READ. The pin's `_resolve` -- `git show
    'ad117c928^:tinygrad/engine/realize.py'` lines 128-131, VERBATIM, the only difference
    being that `Ops.GETADDR` is absent -- is transcribed here and driven on the ORACLE'S OWN
    fixture, so the claim in FINDING 1 is a measurement on every run and not a reading of a
    diff.

    It asserts TWO things and the second is the one that keeps the first honest. The pin
    must AGREE with the port on `res_63` (the GETADDR row), or the drift story is a story.
    And the pin must DISAGREE with the port on `res_52` (the MSTACK row), or every one of
    the 125 would be drift and the drift check would be measuring nothing -- the MSTACK arm
    has been absent from `rz_arm` in BOTH versions, which is what makes "only one arm" a
    measurement instead of an adjective.

    MEASURED, the two rows it compares (the `@<slot>` suffix is `s1`'s `arg=` repair, so
    "WHICH BUFFER" is visible -- `b0` and `b1` printed `BUFFER/1` alike until then):
        HEAD   res_63=BUFFER/1@0+GETADDR/1<-BUFFER/1@1+CONST(1)
        PIN    res_63=BUFFER/1@0+GETADDR/1<-PARAM/0@0+CONST(1)    <-- AND SO DOES THE PORT
        HEAD   res_52=BUFFER/1@0+MSTACK/2<-BUFFER/1@1
        PIN    res_52=BUFFER/1@0+MSTACK/2<-BUFFER/1@1             <-- AND SO DOES NOT THE PORT
    """
    try:
        RO = _load_oracle()
    except Exception as e:                                   # noqa: BLE001
        print(f"  pin_drift_holds: the oracle module would not load: {e}")
        return False

    def pin_resolve(b, inputs):
        if b.op in (Ops.MSELECT, Ops.SHRINK, Ops.BITCAST):
            return b.replace(src=(pin_resolve(b.src[0], inputs), *b.src[1:]))
        if b.op is Ops.MSTACK:
            return b.replace(src=tuple(pin_resolve(x, inputs) for x in b.src))
        return inputs[b.arg.slot] if b.op is Ops.PARAM else b

    def pin_row(n):
        xs = [pin_resolve(b, (RO.b1, RO.b0)) for b in RO.RZ.get_call_arg_uops(RO.B[n])]
        return "+".join(RO.s2(x) for x in xs) or "none"

    port = _lane("bd.out")
    if port is None:
        print("  pin_drift_holds: the promoted port lane is not there")
        return False
    ok = True
    if pin_row(63) != port["res_63"]:
        print(f"  pin_drift_holds: the PIN answers res_63 {pin_row(63)!r} and the port "
              f"{port['res_63']!r} -- FINDING 1's drift story is not what it claims")
        ok = False
    if pin_row(52) == port["res_52"]:
        print(f"  pin_drift_holds: the PIN also answers res_52 {pin_row(52)!r}, so the "
              f"MSTACK wall is drift too and 'only one arm' is wrong")
        ok = False
    return ok


def calls_hold() -> bool:
    """THE 23 CALL NODES, RE-DERIVED FROM THE LANES' OWN `notacall` ROWS.

    `CALLS` is a hand-written index list and it is the ONLY hand-written index list in
    this file; `NONCALL` and `SRC_BODY`'s row set are built from it, so a wrong entry
    moves 52 declared rows. This asks both lanes which nodes they refused to drive, and
    checks that they refused exactly the complement.
    """
    ok = True
    for lane, expect in (("py.rows", "notacall"), ("bd.out", "notacall")):
        rows = _lane(lane)
        if rows is None:
            print(f"  calls_hold: {lane} is not there")
            return False
        for n in range(1, NODES + 1):
            if (rows["oi_%d" % n] == expect) != (n in NONCALL):
                print(f"  calls_hold: {lane} oi_{n}={rows['oi_%d' % n]!r} and CALLS "
                      f"disagree about whether {n} is a CALL")
                ok = False
    return ok


def compares_holds() -> bool:
    """WHAT FRACTION OF THIS CENSUS ACTUALLY COMPARES, MEASURED ON THE PROMOTED LANES.

    `ROWS[0] - len(DIVERGES)` IS NOT THE DENOMINATOR OF A COMPARISON, and the verdict line
    used to print it as if it were. Three kinds of row are inside it and compare nothing:

      * `notacall` -- the CALL-only drivers refusing a non-CALL. BOTH lanes answer the
        literal, so the refusal is an EXACT MATCH and it is counted among the matches;
      * the `BOTTOM` rows -- slot 0 is `Arena.bottom()` and CPython has no such node;
      * nothing else: the twelve `arm_*` rows and the two header rows DO compare.

    So the honest number is `ROWS - refused - len(BOTTOM)`, and it is DERIVED from the
    lanes rather than from a list of driver names: the refusal population is measured, and
    the check is that every driver which refuses at all refuses on ALL `NONCALL` nodes. A
    driver that started refusing on a SUBSET -- which is what a wrong op test on a new
    node would look like -- is a driver whose rows stopped comparing, and the exact-match
    count would not move, so nothing else here would say so.
    """
    port, cpy = _lane("bd.out"), _lane("py.rows")
    if port is None or cpy is None:
        print("  compares_holds: the promoted lanes are not there")
        return False
    ok = True
    nc = tuple(n for n in range(1, NODES + 1) if n not in CALLS)
    for drv in DRV:
        hit = [n for n in nc if cpy.get("%s_%d" % (drv, n)) == "notacall"]
        if hit and len(hit) != len(nc):
            print(f"  compares_holds: {drv} refuses on {len(hit)} of {len(nc)} non-CALLs "
                  f"({hit[:6]}...), so its refusal is a SUBSET and those rows stopped "
                  f"comparing without the exact-match count moving")
            ok = False
        for n in nc:
            k = "%s_%d" % (drv, n)
            if cpy.get(k) == "notacall" and port.get(k) != "notacall":
                print(f"  compares_holds: {k} refuses on the CPython lane only")
                ok = False
    refused = sum(1 for k in cpy if cpy[k] == "notacall" and port.get(k) == "notacall")
    # The bottom rows are named, not SHAPED: CPython answers the literal `bottom` and the
    # PORT answers `none`/`notacall`/`0` (there is no node to print), so "both lanes say
    # bottom" is zero of them. What makes them uncomparable is that there is nothing on
    # the CPython side to compare TO -- `no_bottom_value` holds the port's half.
    bottom = sum(1 for r in BOTTOM if cpy.get(r) == "bottom")
    if bottom != len(BOTTOM):
        print(f"  compares_holds: {bottom} of {len(BOTTOM)} bottom rows read `bottom` on "
              f"the CPython lane; slot 0 is `Arena.bottom()` and CPython has no such node")
        ok = False
    want_refused, want_bottom = _compared()[1], _compared()[2]
    if (refused, bottom) != (want_refused, want_bottom):
        print(f"  compares_holds: the lanes hold {refused} refusals and {bottom} bottoms "
              f"and the verdict line DERIVES {want_refused} and {want_bottom}, so the "
              f"'only N rows carry a comparison' claim disagrees with the lanes")
        ok = False
    if refused % len(nc):
        print(f"  compares_holds: {refused} refusals is not a whole number of "
              f"{len(nc)}-node sweeps, so a driver refused on a SUBSET of its rows")
        ok = False
    return ok


def _compared() -> tuple[int, int, int]:
    """`(compared, refused, bottom)`, DERIVED from the population rather than read off
    disk, because the verdict line is formatted BEFORE `gatekit` runs and `gatekit`
    EMPTIES the output directory on the way in -- reading the lanes there reads nothing
    (MEASURED: the first version of this printed `0` of `974` and still exited 0).

    The refusal population is the ORACLE'S OWN `CALL_ONLY` declaration, loaded by path,
    times the 41 NON-CALL nodes: a CALL-only driver refuses every non-CALL and refuses
    nothing else. `compares_holds()` then measures both facts off the promoted lanes, so
    this is a CLAIM the lanes confirm rather than a second reader.
    """
    try:
        refused = len(_load_oracle().CALL_ONLY) * len(NONCALL)
    except Exception:                                         # noqa: BLE001
        refused = 0
    return (ROWS[0] - refused - len(BOTTOM), refused, len(BOTTOM))


def kern_blind_holds() -> bool:
    """THE `kern` DRIVER COMPARES A COUNT WHERE THE THINGS ARE NAMES, AND THIS IS THE
    MEASUREMENT THAT SAYS WHY IT CANNOT BE MORE, ON BOTH SIDES, TODAY.

    **BOX 1.** `realize.py:41` is `[(d, call, None) for d in to_tuple(call.src[1].device)]` --
    the answer IS a list of device NAMES -- and `rs_d_kern` prints `len()` of the port's list
    of device TAGS. Three measurements, all re-taken by this function:

      1. **THE PORT'S LIST IS ALREADY THERE AND IS THROWN AWAY.** `get_call_kernels`
         (realize.bend:679) answers `List<&2, U32>` and `dev_tags` (realize.bend:650)
         returns `D1{tag}` -> `[tag]` and `Dn{tags}` -> `tags`. So printing the tags is a
         one-line change and it is NOT made here, for (2) and (3).
      2. **`Device.tag` DOES NOT EXIST IN THIS TREE'S CPYTHON.** `uop/spec.bend:1488`
         calls it "the table that interns a device NAME ... `Device.tag`, which is P6", and
         `gates/realize_graph_census-gate.py`'s own previous text repeated it. MEASURED,
         `.venv/bin/python`: `type(Device)` is `tinygrad.device._Device` (`device.py:21`,
         `:62`) and `hasattr(Device, 'tag')` is **False**. The table the port inherits and
         does not check is a table CPython does not have -- so the port's tag has NO
         CPython counterpart, and a cross-lane tag comparison would be comparing two
         fixtures' private numbering with nothing to say they agree.
      3. **THE PORT'S OWN ONLY TAG/NAME FUNCTION IS A THREE-VALUED SENTINEL, AND A SECOND
         ONE DISAGREES WITH IT.** `device.bend:344 tag_of` is DISK 6, NPY 10, PYTHON 13,
         EVERYTHING ELSE 0 -- built to decide `ALLOW_DEVICE_USAGE` (`device.py:31`), and it
         puts CPU, METAL, AMD, NV, CUDA, QCOM, CL, DSP, WEBGPU and every typo on the same
         0. And `schedule/memory.bend:999` is `disk() = S.D1{1}`, where `tag_of("DISK")` is
         6; `uop/validate.bend:2532` records the disagreement and refuses to arbitrate it.
         **SO `S.D1{tag}` IS NOT AN INDEX INTO ANY DEVICE TABLE THE PORT OR CPYTHON HAS.**

    What it checks instead is the property that IS decidable: that the fixture's multi-device
    answer is a list of TWO, that its two tags are DISTINCT, and that both lanes print 2.
    Before this, every device in the fixture was a scalar `S.D1` and every `kern_*` row was
    a list of length 0 or 1, so `len()` -- the one projection both sides share -- was only
    ever tested on a list that could not surprise it. `rs_x64`/`rs_x65` minted a
    `S.Dn{[6, 0]}` over `("DISK", "CPU")` and a CALL over it, so `kern_65` is now 2 on both
    lanes and a dropped or duplicated device moves the count.

    **WHAT IT STILL CANNOT DISTINGUISH, STATED RATHER THAN ASSERTED AWAY:** an ORDER SWAP
    inside `Dn{[6, 0]}`, and any tag that is wrong but drawn from a space the port and
    CPython do not share. There is no vocabulary to be wrong in. The ceiling is a DECLARED
    BLINDNESS, and the measurement above is why the closure is not available in this layer
    or in any layer: the fix would be `Device.tag`, which does not exist.
    """
    census = _code((HERE / "realize_graph_census.bend").read_text())
    port_src = census + "\n" + _code(PORT.read_text())
    # THE MINT IS A `S.Dn{[...]}` OR A `S.D1{N}`; THE MATCH ARM IS `S.D1{tag}`.
    # Measured before this was written: `S.D1{` occurs once in the port and that one is
    # `realize.bend`'s `dev_tags` arm -- a grep for the shape alone would have called it a
    # second device and taken this gate red for nothing.
    multi = re.findall(r"S\.Dn\{\[([^\]]*)\]\}", port_src)
    try:
        oracle_src = _code((HERE / "realize_graph_census-oracle.py").read_text())
    except OSError:
        print("  kern_blind_holds: the oracle source is not readable")
        return False
    py_multi = re.findall(r'_buf_dev\(\d+, "[^"]*", \(([^)]*)\)\)', oracle_src)
    ok = True

    def bad(msg):
        nonlocal ok
        print(f"  kern_blind_holds: {msg}")
        ok = False

    if len(multi) != 1:
        bad(f"the PORT fixture mints {len(multi)} multi-device devices, this check needs "
            f"exactly one, or `len()` is only ever tested on a list of length 0 or 1")
    elif [t.strip() for t in multi[0].split(",")] != ["6", "0"]:
        bad(f"the PORT fixture's multi-device is `S.Dn{{[{multi[0]}]}}'` and its two tags "
            f"are not DISTINCT, so a duplicated device would not move the count")
    if len(py_multi) != 1:
        bad(f"the CPython fixture mints {len(py_multi)} multi-device devices, this check "
            f"needs exactly one")
    elif [d.strip().strip('"') for d in py_multi[0].split(",")] != ["DISK", "CPU"]:
        bad(f"the CPython fixture's multi-device is ({py_multi[0]}), not two DISTINCT names")
    # AND THE ROW THAT USES IT, OFF THE PROMOTED LANES -- so this is a claim about what the
    # gate PRINTED and not about what the source says.
    for lane in ("bd.out", "py.rows"):
        rows = _lane(lane)
        if rows is None:
            bad(f"{lane} is not there")
            continue
        if rows.get("kern_65") != "2":
            bad(f"{lane} kern_65={rows.get('kern_65')!r} and the multi-device CALL's count "
                f"is 2, so the one row that can surprise `len()` does not")
    return ok


if "--refresh" in sys.argv:
    sys.exit(refresh())
if DIVERGES is None:
    print(f"realize_graph_census-gate: REFUSED, NOT A VERDICT: {WHY}", file=sys.stderr)
    sys.exit(REFUSED)

GATE = Gate(
    "realize_graph_census-gate",
    bend="realize_graph_census.bend",
    oracle="realize_graph_census-oracle.py",
    rows=ROWS[0],
    compared=ROWS[0] - len(DIVERGES),
    diverges=DIVERGES,
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ("arena_n", "rows")
          ] + [(lane, "arm_%s" % a) for lane in ("py", "bd", "bn")
               for a in ("PROGRAM", "STORE", "CUSTOM_FUNCTION", "RANGE", "PARAM", "SINK",
                         "LINEAR", "MSELECT", "SHRINK", "BITCAST", "MSTACK", "GETADDR")],
)


if __name__ == "__main__":
    sys.exit(gate(
        GATE,
        f"realize_graph_census-gate: {ROWS[0]} rows ({len(DRV)} drivers x {NODES} nodes + "
        f"{len(DRV)} bottom + 12 arm-coverage + 2 header), 3 lanes, "
        f"{ROWS[0] - len(DIVERGES)} answers match CPython byte-for-byte and "
        f"{len(DIVERGING)} are DECLARED divergences over NINE classes -- "
        f"OF THOSE {ROWS[0]} ROWS ONLY {_compared()[0]} CARRY A COMPARISON: "
        f"{_compared()[1]} are the CALL-only drivers refusing a non-CALL "
        f"(both lanes answer `notacall`, so they count as matches) and {_compared()[2]} "
        f"are `Arena.bottom()`, where CPython has no node. "
        f"{len(BOTTOM)} divergences are that bottom, "
        f"{len(NAME_ARM)} are `get_call_name`'s STORE arm and its fallthrough, "
        f"{len(VARS_BODY)} are `prg.arg.vars` over a non-`ProgramInfo` body, "
        f"{len(VAL_BODY)} are `pm_validate`'s UNPORTED BODY (claim against cone), "
        f"{len(ARG_SLOT)} are a CALL whose `src[1]` is not a PARAM or a BUFFER, "
        f"{len(SLOT_MISS)} are `inputs[slot]` where CPython has no default, 1 is the "
        f"MSELECT `storage_base` wall, 1 the MSTACK walk. THE `SRC_BODY` CLASS IS GONE: "
        f"{len(SRC_BODY_FIXED)} rows that used to be realize.py:15's UNCONDITIONAL "
        f"`src[1:]` against the port's op-CONDITIONAL `Arena.src_without_body` now AGREE, "
        f"and `classes_hold` asserts every one of them still does -- **AND `rz_bound_map`, "
        f"the SECOND of its two fix sites, IS NOT COVERED BY ANY OF THEM: MEASURED, "
        f"reverting it moves ZERO rows, because no driver reaches `get_call_var_uops` on a "
        f"non-CALL (`var` is refused there by `u.body`) and for a CALL the two spellings "
        f"ARE the same slice. The port's own comment says so; this header did not.** "
        f"ONE FINDING STANDS: "
        f"`res_63` -- HEAD's `_resolve` has an `Ops.GETADDR` arm and `rz_arm` does NOT, so "
        f"a GETADDR argument is left un-resolved; IT VANISHES UNDER THE PIN "
        f"`ad117c928^`, whose line 129 has no GETADDR, so the port is correct against the "
        f"pin and incomplete against HEAD, and `pin_drift_holds` runs the pin's code on "
        f"every run to keep saying so. `ret is not uop` IS FIXED: the "
        f"{len(RET_IS_UOP_FIXED)} `bea0_*` rows agree on `10` -- CLAIMED and the rewrite "
        f"was the identity -- and the ctx-7 rows still begin `11` and carry `b=7`. "
        f"**THE TWO BITS ARE WHY `rz_kernel_beam`'s NO-`KernelInfo` DEFAULT IS A ROW AT "
        f"ALL: with the old single bit, mutating that default `0` -> `1` moved ZERO of the "
        f"rows (`V2`, reported as vacuous), because the claim was folded away.** THE `kern` "
        f"DRIVER COMPARES A COUNT WHERE THE THINGS ARE NAMES, and `kern_blind_holds` "
        f"measures why that is the CEILING -- `Device.tag` does not exist in this tree's "
        f"CPython (`hasattr(Device,'tag')` is False) and the port's own `tag_of` is a "
        f"three-valued sentinel -- while a NEW TWO-DEVICE node makes the count 2 on both "
        f"lanes for the first time. THE DRIVER AXIS IS READ BACK FROM FOUR PLACES BY "
        f"`axis_hold`: the oracle's `DRIVERS` BY PATH, the oracle's `drive` ladder, and the "
        f"bend lane's own `rs_drv_name` and `rs_d.go`.",
        checks=lambda: (classes_hold() and no_bottom_value() and drivers_hold()
                        and axis_hold() and calls_hold() and pin_drift_holds()
                        and compares_holds() and kern_blind_holds()
                        and ret_is_uop_fixed_holds())))

# ===========================================================================
# THE TWO FINDINGS, WITH THEIR MEASUREMENTS, AND WHAT WAS DONE ABOUT THEM.
# `tinybendygrad/engine/realize.bend` IS LEFT BYTE-IDENTICAL.
#
# FINDING 1 -- `res_63`, `_resolve` HAS NO `OpsGETADDR` ARM. `rz_arm` (realize.bend:1048)
# reads MSELECT/SHRINK/BITCAST/MSTACK/PARAM and a default; HEAD's `realize.py:129` is
# `if b.op in (Ops.MSELECT, Ops.SHRINK, Ops.BITCAST, Ops.GETADDR)`. So a GETADDR in a
# CALL's argument slot is handed back UNCHANGED where HEAD resolves through it, and the
# argument's device address is then read off the UNREALIZED node. MEASURED, on the `vv`
# call, whose second argument is `GETADDR(PARAM g0)` with `inputs = (b1, b0)`:
#     py   res_63=BUFFER/1+GETADDR/1<-BUFFER/1
#     bd   res_63=BUFFER/1+GETADDR/1<-PARAM/0
# THE PIN IS WHERE IT VANISHES. `git show 'ad117c928^:tinygrad/engine/realize.py'` line 129
# reads `if b.op in (Ops.MSELECT, Ops.SHRINK, Ops.BITCAST):` -- no GETADDR -- so the port's
# five arms are exactly the pin's five arms and the row would AGREE. THE OTHER HALF OF
# THE PIN-CHECK: `git diff --stat 'ad117c928^' HEAD -- tinygrad/engine/realize.py` is
# `15 insertions(+), 14 deletions(-)` and the working-tree blob equals
# `ad117c928`'s, so HEAD IS THE RE-VENDOR AND THE PIN IS NOT WHAT RAN. **SO THE HONEST
# SENTENCE IS BOTH: THE PORT IS CORRECT AGAINST THE PIN AND INCOMPLETE AGAINST WHAT
# ACTUALLY RUNS, AND THE ROW IS PINNED AS A DECLARED DIVERGENCE RATHER THAN SMOOTHED.**
# The other four hunks are all outside the ported arms and all say so: three
# `ast.arg == "encdec"` become `ast.arg.name == "encdec"` (the port's `arg_is_encdec`
# matches HEAD's `.name` spelling, so the port is RIGHT against HEAD and would be WRONG
# against the pin), `exec_kernel` inlines `ast.arg.vals`, `exec_hcq` loses its
# `info.inputs` address table, and `run_linear` gains an assert. All four are group [b].
#
# WHAT IT TOOK TO SEE IT, and both halves are PRINTER decisions rather than port facts.
#   * A GETADDR OVER A **BUFFER** IS INVISIBLE. HEAD's `_resolve` recurses into `src[0]`,
#     `_resolve(BUFFER)` returns it unchanged, the rebuilt GETADDR is content-identical and
#     `UOp.new` hash-conses. MEASURED: with only node 47 (`GETADDR(BUFFER g0)`) in the
#     fixture, `res_51` and `arg_51` AGREED on both sides -- and `arg_51` agrees trivially,
#     since `_resolve`'s view arm only changes a node that is an ARGUMENT of the call, and
#     node 51's own src[0] is a SINK. Node 62 (`GETADDR(PARAM g0)`) is the one that parts.
#   * `inputs` MUST NOT BE TWO PARAMs. `g0` and `g1` are both `PARAM/0`, so a slot lookup
#     of either prints `PARAM/0` and `realize.py:131` becomes invisible. MEASURED: with
#     `inputs=(g1, g0)` -- realize.bend's OWN `res_slot0`/`res_slot1` fixture -- `res_63`
#     AGREED. With `inputs=(b1, b0)` it does not. THAT IS THE SAME LESSON AS
#     `decomp_graph_census`'s CONST-value hole, on a different field: a value that is in no
#     node shape cannot be gated by a printer that does not print it.
#
# FINDING 2 -- THE EIGHT `bea0_*` ROWS, `pm_beam` HAS NO `ret is not uop`.
# `ops.py:1613-1619` is
#     if (ret:=match(uop, ctx)) is not None and ret is not uop: return ret
# so an answer that IS THE NODE ITSELF is dropped. `pm_beam`'s body (realize.py:218) is
# `call.replace(src=(sink.replace(arg=replace(sink.arg, beam=ctx)), *call.src[1:]))`, and
# at `ctx == 0` over a SINK whose `beam` is already 0 EVERY replacement is the identity, so
# `UOp.new` hash-conses and the answer is the input node. MEASURED, `bea0` at ctx 0:
#     py   bea0_23=0
#     bd   bea0_23=1:CALL/2,SINK/0,PARAM/0:b=0
# and the SAME defect at ctx 7 does not fire, because the rewrite really changes the node:
# `beam_23` is byte-identical on both sides (`1:CALL/2,SINK/0,PARAM/0:b=7`). `realize.bend`'s
# `bm_new` answers an `O.Found` -- its own header records that handing back a bare index
# left `bm_new` building the CALL against a stale arena -- and an `O.Found` has no way to
# say "no answer" for a node that IS the answer. THE FIX, IF ONE IS EVER MADE, IS `rz_fire`
# COMPARING THE ANSWER'S INDEX WITH THE INPUT'S, which is the same shape as the
# `M.hop_self` that `rangeify.bend` now carries at all eleven `*_try.of` sites.
# `bea0` IS DRIVEN AT ctx 0 ONLY BECAUSE OF THIS ROW; `beam` at ctx 7 is the same table.
#
# AND WHAT THE PRINTER HAD HIDDEN, WHICH IS THE SECOND HALF OF FINDING 2'S STORY. The
# eight rows above AGREE, and they agreed while the `beam` rows printed ONE BIT, so the
# census could not say WHICH of two worlds produced a `0`: "the rule did not claim" and
# "the rule claimed and the rewrite was the identity". MEASURED, both printed `0` --
# `beam_1` (a CONST, `rz_claim` false) and `bea0_23` (a zero-beam SINK, claim true) -- and
# that collapse is the whole reason mutation `V2` moved ZERO of the rows: `rz_kernel_beam`'s
# no-`KernelInfo` default is read ONLY by `bm_zero`, which is the CLAIM, on the one node
# whose rewrite is the identity. `<claim><fired>` is now the answer on BOTH lanes, so
# `V2` moves `beam_55` and `bea0_55` (MEASURED, 2 rows, rc=1) and `V4` (`bm_zero` always
# true) moves `beam_24`/`bea0_24`. It also found a DRIVER DEFECT on the way: `rs_d_beam`
# used to call `RZ.bm_new` on EVERY node and fold the claim into a `Bool.and`, so
# `pm_beam`'s body ran over nodes its own judge had refused -- and `beam` is not a
# CALL-only driver, so that was a body over a CONST. CPython never had the defect:
# `PatternMatcher.rewrite` calls the body INSIDE the claim.
# ===========================================================================
# ===========================================================================
# THE THREE THINGS THE BRIEF ASKED ABOUT BY NAME, AND WHAT REALIZE ANSWERS.
#
# (b) THE `OpsCAST{}` TRIAGE. MEASURED: `grep -c 'OpsCAST' tinybendygrad/engine/realize.bend`
# is **0**. Realize mints no CAST at all, so there is no site to triage here and saying
# otherwise would be a finding manufactured out of a grep that ran on the wrong file. The
# tree-wide count this brief quotes is ~100 and most of its hits are pattern-matcher arms
# and rewrites where an identity fold would be WRONG; none of them is in this file.
#
# (f) `ret is not uop`. IT APPLIES, AND IT IS FINDING 2. `ops.py:1618` is
# `if (ret:=match(uop, ctx)) is not None and ret is not uop: return ret`. Realize builds
# graphs in TWO places -- `pm_beam`'s body and `_validate`'s -- and `pm_beam` is the one
# that can answer its own input, because at `ctx == 0` over a zero-beam SINK every
# replacement in realize.py:218 is the identity. `rz_beam_sink` already returns an `O.Found`
# rather than a bare index for the stale-arena reason and has no way to say "no answer" for
# a node that IS the answer. The eight `bea0_*` rows ARE that measurement. `pm_flatten_linear`
# CANNOT produce it -- its `custom_early_reject={Ops.LINEAR}` rejects a LINEAR with no
# LINEAR child BEFORE the body runs, so the only rows where its body would be the identity
# are rows it refuses, and `flat_26`/`flat_36` AGREE on both sides. `pm_validate`'s body
# always mints `UOp.new_buffer`, so it never answers its input either -- but it is not
# ported at all, so the question does not arise here.
#
# THE DEAD-NODE QUESTION, IN BOTH DIRECTIONS. `codegen/decomp/dtype.bend`'s `l2i_cast0`
# builds a sign-extension branch UNCONDITIONALLY and discards it in `pick`, where
# `dtype.py:31` returns early -- and a root-walking printer CANNOT SEE the discarded nodes,
# so the gate says so rather than claiming agreement. Realize has no such shape: MEASURED,
# its arena has **no unreferenced non-root node at all**, and the census says so on every
# run by ROWING EVERY SLOT BY INDEX rather than walking from a root. The census fixture
# this gate carries DID have one until its last edit -- slot 42's `CONST 1`, which nothing
# referenced, so `res_42` was a row answering a node nothing in the graph points at -- and
# both lanes now reference it from the `vv` call. THE REMAINING 21 UNREFERENCED SLOTS ARE
# ALL `CALL` OR `LINEAR`, WHICH ARE REALIZE.PY'S OWN ROOTS (`run_linear` iterates
# `linear.src`, `lower_and_compile` walks `linear.toposort()`), so "unreferenced" there is a
# fact about roots and not about garbage. Realize's own record of the class is at its
# header: `pa_bound.of` answered `None{}` for every `Arg`, and `rz_beam_sink` returned a
# bare index from an arena it had grown. BOTH ARE ALREADY FIXED AND BOTH WERE FOUND BY
# ROWS LIKE THESE.
# ===========================================================================
