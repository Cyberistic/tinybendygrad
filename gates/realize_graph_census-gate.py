#!/usr/bin/env python3
"""realize_graph_census-gate.py -- A GRAPH CENSUS over
`tinybendygrad/engine/realize.bend`, the port of `tinygrad/engine/realize.py`.

    .venv/bin/python gates/realize_graph_census-gate.py
    .venv/bin/python gates/realize_graph_census-gate.py --refresh   # rewrites the pins file

974 ROWS (15 DRIVERS x 63 NODES + 15 BOTTOM + 12 ARM-COVERAGE + 2 HEADER), THREE LANES,
849 EXACT MATCHES AND 125 DECLARED DIVERGENCES -- 9 CLASSES, AND 2 FINDINGS.

`realize.py` is 297 lines and the port is 281 defs, and `realize.bend` ships its own
50-row `main` (realize.bend:1992) whose expectations were read out of a live CPython run.
What was ungated was the ANSWER against CPython'S: nothing compared a port reader to the
function it ports, so a reader that returned the wrong list agreed with itself. This is
that lane, and it found two things.

THE POPULATION IS THE (DRIVER, NODE) PRODUCT, AND BOTH AXES ARE DISCOVERED. A ROW is a
pair. NODE ranges over `realize.bend`'s own `main_arena` (its 42 slots, index for index)
PLUS the twenty-two nodes `gates/realize_graph_census.bend` chains onto it, each named in
that file by the dispatch arm it exists for: `main_arena` has no MSELECT, no GETADDR, no
MSTACK, no SHRINK, no SINK without a `KernelInfo`, no PROGRAM whose kernel is unnamed and
no MSELECT in an `outs` slot, so `rz_arm`'s MSELECT/SHRINK/MSTACK arms, HEAD's GETADDR
arm, `gcc_sink`'s and `gcc_pick.prog`'s DEFAULT arms, `gn_prog`'s default arm and
`get_call_written_bufs`'s MSELECT wall would ALL have been unreachable rows. DRIVER
ranges over FIFTEEN, and `drivers_hold()` re-derives the set on every run:

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
pairs fire hide inside the filter. `rows` is PRINTED by both lanes and is 974.

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

THE TWO FINDINGS, AND BOTH ARE PORT DEFECTS. `tinybendygrad/engine/realize.bend` IS LEFT
BYTE-IDENTICAL; these are REPORTED, not fixed.

  FINDING 1 -- `res_63`, `_resolve` HAS NO `OpsGETADDR` ARM. `rz_arm` (realize.bend:976)
  reads `OpsMSELECT OpsSHRINK OpsBITCAST OpsMSTACK OpsPARAM` and HEAD's `realize.py:129`
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
  `bea0` at `ctx=0` on the `l` call: CPython answers `0` and the port answers
  `1:CALL/2,SINK/0,PARAM/0:b=0`. `beam_0` IS THE SAME DEFECT AT A DIFFERENT ctx AND IS
  NOT COUNTED TWICE: at `ctx=7` the rewrite really changes the node and the two sides
  agree on the cone AND on the beam. `realize.bend`'s `bm_new` returns an `O.Found`
  rather than a bare index (its own header records why) and has no way to say "no answer"
  for a node that IS the answer; `rz_graph_census` here drives `beam` at TWO ctx values
  precisely so the defect has a row.

THE 125 DIVERGENCES, CLASSIFIED, PINNED ON BOTH SIDES, AND EVERY CLASS MEASURED.

  52 `SRC_BODY` -- `arg_*` and `res_*` over the 41 NON-CALL nodes that diverge.
      `realize.py:15` is `tuple(s for s in call.src[1:] ...)` -- an UNCONDITIONAL slice --
      and the port's `get_call_arg_uops` is `O.Arena.src_without_body` (realize.bend:265),
      which is `src[1:]` FOR A CALL AND `src` FOR EVERYTHING ELSE, because that is what
      `UOp.src_without_body` does (ops.py:1329). MEASURED: on the `g` STORE call the two
      agree (`arg_18`), and on a 3-src BUFFER body the port answers one extra entry. The
      direction is SAFE -- EXTRA arguments where realize.py passes a CALL and can never
      happen -- and 30 of the 82 candidate non-CALL pairs agree anyway, so the class is the
      52 that MOVE rather than all 82.

  15 `BOTTOM` -- `Arena.empty` spends slot 0 on `bottom()` and CPython has no such node,
      so there is nothing to compare and the row says `bottom`. `no_bottom_value` says the
      port never answers a VALUE there, which is the shape a stale-arena self-loop takes.

  14 `NAME_ARM` -- `get_call_name` (realize.py:43). The port implements the PROGRAM arm
      alone; the STORE and `encdec` arms need `sym_infer` (GENERATED SOURCE, ops.py:1177)
      and the fallthrough is a `raise`, which the port spells `none`. Twelve rows are the
      `NotImplementedError`, one is `encdec`'s ANSI-coloured string (`realize.py:50`, the
      escape codes are part of the pin and nothing is stripped) and one is `name_57`, whose
      PROGRAM's `src[0]` is a SINK with `arg=None` and CPython raises `AttributeError`.

  12 `VARS_BODY` -- `get_call_var_uops` (realize.py:16) reads `prg.arg.vars`, which is a
      `ProgramInfo` field; over a SINK or a `CustomFunction` body CPython raises
      `AttributeError` and the port's `rz_pvars.go` (realize.bend:487) answers `Nil{}`.

  11 `VAL_BODY` -- `pm_validate`'s BODY is not ported. `validate_table()` is read by
      `t_va_len` alone (realize.bend:1175) and `_validate`'s `UOp.new_buffer` and
      `store_call` are `TODO(p3)`, so the port has a CLAIM and no graph and this lane
      compares a claim against a cone. Nine rows are that, `val_50`/`val_53` are CPython
      raising inside `_validate`, and `val_27` is `pm_validate` tag 1 -- `pm_flatten_linear`
      carried in by `PatternMatcher.__add__` -- firing where the port has no second scan.

  8 `ARG_SLOT` -- a CALL whose `src[1]` is NOT a PARAM or a BUFFER. `gcc_53` is a SINK
      (`c.device` is `None`, so `c.device[0]` raises `TypeError`), `gcc_50`/`gcc_60` are
      MSELECT and GETADDR (`Device[c.device]` asserts), `kern_53` is a SINK (CPython's
      `to_tuple(call.src[1].device)` answers one device and the port's `PArg.of` reads no
      `ParamArg`, so it answers NONE), `nb_53` is `prod(shape)` on a SINK, `est_57` is a
      PROGRAM whose `src[0].arg` is `None`, and `beam_55`/`bea0_55` are a SINK with no
      `KernelInfo`, where CPython raises `AttributeError` on `sink.arg.beam` and the port's
      `rz_kernel_beam` (realize.bend:1193) DEFAULTS IT TO ZERO. Every one of these is out
      of context: `realize.py` only ever puts a PARAM or a BUFFER in a CALL's argument
      slot, and none of them is reachable from a real graph. `rz_kernel_beam`'s default is
      the one with a wrong ANSWER rather than a missing one -- it makes a bodyless SINK
      fire `pm_beam` -- and it is pinned separately as `SINK_NO_KI` inside this class.

  2 `SLOT_MISS` -- `res_20` and `res_22`. `_resolve` ends `inputs[b.arg.slot]` with no
      default and CPython raises `IndexError`; the port's `rz_res.at` (realize.bend:994)
      is `Maybe.default(..., b)`, a default CPython does not have. That default is RIGHT
      for `get_call_var_uops`'s `bound.get(v.expr, v)` and WRONG here -- the two readers
      share one helper and only one of them defaults. Safe direction: the argument points
      at the node the caller already had.

  1 `MSELECT_WALL` -- `wbuf_60`. `realize.py:32` resolves an MSELECT argument through
      `b.src[0].storage_base` and CPython answers `BUFFER/1`; the port's own header
      (realize.bend:575-580) records `storage_base` as a wall (`ops.py:798`) and the
      `O.OpsBUFFER` test drops it.

  1 `GETADDR_DRIFT` and 8 `RET_IS_UOP` are the two FINDINGS above.

WHAT IT ASSERTS THAT NEEDS NO CPYTHON. `no_bottom_value`: neither port lane answers a
VALUE at slot 0, which is what `Arena.bottom()` being read as a real node would look like.
`arms_all_reached`: all twelve arm-coverage rows are non-zero, so every op tag realize's
dispatchers name has a fixture node that reaches it. `drivers_hold`: the driver axis is
still the measured intersection.

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
# the order is part of the contract and it is the order the oracle prints.
DRV = ("arg", "nb", "res", "flat", "val", "beam", "bea0", "oi", "wbuf", "kern",
       "name", "est", "var", "gcc", "dnum")
NODES = 63

# THE 22 CALL NODES, MEASURED: `oi_<n> == "notacall"` on BOTH lanes iff `n` is not one of
# these, and `calls_hold()` re-derives it from the promoted lanes on every run. It is the
# fixture's own index map, read off `main_arena`'s comment (realize.bend:1373-1401) plus
# the twenty-two nodes the census adds, and it is written down so the class tuples below
# can be comprehensions rather than 125 literals.
CALLS = (17, 18, 19, 20, 21, 22, 23, 24, 25, 31, 35, 40, 49, 50, 51, 52,
         53, 55, 57, 60, 61, 63)
NONCALL = tuple(n for n in range(1, NODES + 1) if n not in CALLS)

# THE CLASSIFICATION, HAND-DECLARED, AND EVERY NUMBER IN IT MEASURED. This tuple set IS
# the divergence POPULATION -- it is written here, in git, and the pins file is checked
# against it in BOTH directions, so neither can drift alone.
BOTTOM = tuple("b_" + d for d in DRV)
SRC_BODY = (
    "arg_9", "arg_10", "arg_11", "arg_12", "arg_13", "arg_14", "arg_15", "arg_16",
    "arg_26", "arg_27", "arg_28", "arg_29", "arg_30", "arg_33", "arg_34", "arg_36",
    "arg_39", "arg_41", "arg_45", "arg_46", "arg_47", "arg_48", "arg_56", "arg_58",
    "arg_59", "arg_62",
    "res_9", "res_10", "res_11", "res_12", "res_13", "res_14", "res_15", "res_16",
    "res_26", "res_27", "res_28", "res_29", "res_30", "res_33", "res_34", "res_36",
    "res_39", "res_41", "res_45", "res_46", "res_47", "res_48", "res_56", "res_58",
    "res_59", "res_62",
)
NAME_ARM = ("name_18", "name_21", "name_22", "name_23", "name_24", "name_49", "name_50",
            "name_51", "name_52", "name_53", "name_55", "name_57", "name_61", "name_63")
VARS_BODY = ("var_21", "var_22", "var_23", "var_24", "var_49", "var_50", "var_51",
             "var_52", "var_53", "var_55", "var_61", "var_63")
VAL_BODY = ("val_23", "val_24", "val_27", "val_49", "val_50", "val_51", "val_52",
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

    # SRC_BODY: `Arena.src_without_body` drops `src[0]` FOR A CALL AND NOTHING ELSE, so over
    # a NON-CALL the port's answer is EXACTLY `src[0]` followed by CPython's -- one entry
    # longer, at the HEAD. Checked as a SUFFIX and a length, on every row: a prefix test
    # would have passed the 6 rows it rejected (MEASURED, `arg_27`, `arg_39`, `arg_45` and
    # their `res_` twins) and a count alone would pass anything.
    for r in SRC_BODY:
        c, q = cpy[r], port[r]
        okrow = len(q.split("+")) == 1 if c == "none" else q.endswith("+" + c) and len(q.split("+")) == len(c.split("+")) + 1
        if not okrow:
            bad(f"{r}: port {q!r} is not CPython {c!r} with ONE entry prepended")
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
    # `KernelInfo`, and the port's `rz_kernel_beam` DEFAULTS it to 0 -- so the rule fires on
    # a node CPython cannot run at all. BOTH CONTEXTS NOW ANSWER `0`, and that is the
    # `ret is not uop` clause rather than a disappearance: `rz_beam_sink.go`'s `_` arm (its
    # own header's reason) leaves a bodyless SINK alone, so the CALL `bm_new` rebuilds is
    # CONTENT-IDENTICAL to `CALL(54, 2)` -- node 55 itself -- and hash-conses to it. The port
    # answers "no rewrite" at ctx 7 TOO, which is right: there was never a rewrite to make.
    for r in SINK_NO_KI:
        if cpy[r] != "raise=AttributeError" or port[r] != "0":
            bad(f"{r}: cpy={cpy[r]!r} port={port[r]!r}, not the declared SINK_NO_KI pair")
    # SLOT_MISS: CPython raises IndexError on `inputs[slot]` and the port defaults to the
    # node, so the port's answer CONTAINS the node CPython refused to look up.
    for r in SLOT_MISS:
        if cpy[r] != "raise=IndexError" or port[r] == "none":
            bad(f"{r}: cpy={cpy[r]!r} port={port[r]!r}, not the declared SLOT_MISS pair")
    # MSELECT_WALL: CPython resolves the MSELECT to its storage base and the port drops it.
    if (cpy["wbuf_60"], port["wbuf_60"]) != ("BUFFER/1", "none"):
        bad(f"wbuf_60: cpy={cpy['wbuf_60']!r} port={port['wbuf_60']!r}, "
            f"not the declared MSELECT wall")
    # GETADDR_DRIFT, THE VENDORED-DRIFT FINDING: the SAME node with the SAME op and arity,
    # differing only in what `src[0]` BECAME. One more level is the whole instrument.
    if (cpy["res_63"], port["res_63"]) != ("BUFFER/1+GETADDR/1<-BUFFER/1+CONST(1)",
                                           "BUFFER/1+GETADDR/1<-PARAM/0+CONST(1)"):
        bad(f"res_63: cpy={cpy['res_63']!r} port={port['res_63']!r}, "
            f"not the declared GETADDR drift pair")
    # RET_IS_UOP, NOW FIXED: at ctx 0 both lanes answer `0`, and the ctx-7 rows answer the
    # same CONE **and the same BEAM**. `ret_is_uop_fixed_holds()` is the separate claim; this
    # is the guard that the fix did not move the OTHER context.
    for r in RET_IS_UOP_FIXED:
        if cpy[r] != "0" or port[r] != "0":
            bad(f"{r}: cpy={cpy[r]!r} port={port[r]!r}, and the ctx-0 row must be '0' on "
                f"BOTH sides now that `bm_new` carries `M.hop_self`")
    return ok


def ret_is_uop_fixed_holds() -> bool:
    """FINDING 2 IS FIXED, AND THIS IS THE ROW THAT WOULD CATCH A REGRESSION.

    `pm_beam`'s clause is CONTEXT-DEPENDENT, so a fix that made ctx 7 disagree would be a
    regression and not a fix. The census drives `beam` at ctx 7 and `bea0` at ctx 0 for
    exactly that reason, and this check holds both halves: the eight ctx-0 rows are
    byte-identical on the lanes (the clause drops the identity rewrite), and the ctx-7 rows
    still carry `b=7` -- a `M.hop_self` that dropped too eagerly would make them `0` or
    `b=0`, and both are caught here.
    """
    ok = True
    for lane in ("bd.out", "bn.out"):
        rows = _lane(lane)
        if rows is None:
            print(f"  ret_is_uop_fixed_holds: {lane} is not there")
            return False
        for r in RET_IS_UOP_FIXED:
            if rows[r] != "0":
                print(f"  ret_is_uop_fixed_holds: {lane} {r}={rows[r]!r}, "
                      f"the `ret is not uop` clause is not firing at ctx 0")
                ok = False
        fired = [r for r in rows if r.startswith("beam_") and rows[r] != "notacall"
                 and rows[r] != "0" and not rows[r].startswith("raise=")]
        if not fired:
            print(f"  ret_is_uop_fixed_holds: {lane} has NO ctx-7 row that fired -- "
                  f"a fix that dropped every rewrite would pass the ctx-0 check alone")
            ok = False
        for r in fired:
            if not rows[r].endswith(":b=7"):
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
    """
    for lane in ("bd.out", "bn.out"):
        f = ART / lane
        if not f.is_file():
            return False
        rows = _lane(lane)
        for r in BOTTOM:
            if rows.get(r, "bottom") not in ("none", "notacall", "0"):
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
    if cases != 15:
        print(f"  drivers_hold: `case O.Ops*` is {cases} arms, the file declares 15")
        ok = False
    # (a)'s EIGHT names and (c)'s THREE table drivers are named in the file under the
    # census's OWN short spelling, so the check is membership, and (b)'s THREE and `bea0`
    # are named explicitly. `bea0` is the SAME TABLE as `beam` at a second ctx and it is
    # here because the `ret is not uop` finding has no row without it.
    got = set(DRV)
    want = ({"arg", "res", "oi", "wbuf", "kern", "name", "var", "gcc"}
            | {"flat", "val", "beam"}
            | {"est", "nb", "dnum", "bea0"})
    if len(DRV) != 15 or got != want:
        print(f"  drivers_hold: the declared driver axis is {sorted(got)}, "
              f"expected 15 rows and {sorted(want)}")
        ok = False
    # (a)'s eight REALIZE.PY names are driven under the census's OWN short spelling, so the
    # check is that the MAPPING is total -- a name `realize.py` owns and the axis cannot
    # spell is a driver the census is missing, and saying so beats a hard-coded list.
    SHORT = {"get_call_arg_uops": "arg", "resolve_params": "res", "get_call_outs_ins": "oi",
             "get_call_written_bufs": "wbuf", "get_call_kernels": "kern",
             "get_call_name": "name", "get_call_var_uops": "var",
             "_get_call_to_compile": "gcc", "estimate_uop": "est",
             "unwrap_multi": "nb"}
    miss = sorted({SHORT[n] for n in inter if n in SHORT} - got)
    if miss:
        print(f"  drivers_hold: (a) names map to {miss}, which the axis does not drive")
        ok = False
    unowned = sorted(n for n in inter if n not in SHORT)
    if unowned:
        print(f"  drivers_hold: (a) has no short name for {unowned} -- a new realize.py "
              f"reader would go ungated")
        ok = False
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

    MEASURED, the two rows it compares:
        HEAD   res_63=BUFFER/1+GETADDR/1<-BUFFER/1+CONST(1)
        PIN    res_63=BUFFER/1+GETADDR/1<-PARAM/0+CONST(1)    <-- AND SO DOES THE PORT
        HEAD   res_52=BUFFER/1+MSTACK/2<-BUFFER/1
        PIN    res_52=BUFFER/1+MSTACK/2<-BUFFER/1            <-- AND SO DOES NOT THE PORT
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
    """THE 22 CALL NODES, RE-DERIVED FROM THE LANES' OWN `notacall` ROWS.

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
        f"realize_graph_census-gate: {ROWS[0]} rows (15 drivers x 63 nodes + 15 bottom "
        f"+ 12 arm-coverage + 2 header), 3 lanes, "
        f"{ROWS[0] - len(DIVERGES)} answers match CPython byte-for-byte and "
        f"{len(DIVERGING)} are DECLARED divergences over TEN classes -- "
        f"{len(SRC_BODY)} are realize.py:15's UNCONDITIONAL `src[1:]` against the port's "
        f"op-CONDITIONAL `Arena.src_without_body` (SAFE direction: EXTRA arguments, and "
        f"only out of context), {len(BOTTOM)} are `Arena.bottom()` where CPython has no "
        f"node, {len(NAME_ARM)} are `get_call_name`'s unported STORE/`encdec` arms, "
        f"{len(VARS_BODY)} are `prg.arg.vars` over a non-`ProgramInfo` body, "
        f"{len(VAL_BODY)} are `pm_validate`'s UNPORTED BODY (claim against cone), "
        f"{len(ARG_SLOT)} are a CALL whose `src[1]` is not a PARAM or a BUFFER, "
        f"{len(SLOT_MISS)} are `inputs[slot]` where CPython has no default, 1 is the "
        f"MSELECT `storage_base` wall. AND TWO FINDINGS: `res_63` -- HEAD's `_resolve` "
        f"has an `Ops.GETADDR` arm and `rz_arm` does NOT, so a GETADDR argument is left "
        f"un-resolved; IT VANISHES UNDER THE PIN `ad117c928^`, whose line 129 has no "
        f"GETADDR, so the port is correct against the pin and incomplete against HEAD; "
        f"and the {len(RET_IS_UOP)} `bea0_*` rows -- `pm_beam` has no `ret is not uop`, so "
        f"at ctx 0 it answers the node itself where CPython answers `None`. Both are "
        f"REPORTED, `realize.bend` is left BYTE-IDENTICAL, and no lane answers a value at "
        f"the arena bottom",
        checks=lambda: (classes_hold() and no_bottom_value() and drivers_hold()
                        and calls_hold() and pin_drift_holds()
                        and ret_is_uop_fixed_holds())))

# ===========================================================================
# THE TWO FINDINGS, WITH THEIR MEASUREMENTS, AND WHAT WAS DONE ABOUT THEM.
# `tinybendygrad/engine/realize.bend` IS LEFT BYTE-IDENTICAL.
#
# FINDING 1 -- `res_63`, `_resolve` HAS NO `OpsGETADDR` ARM. `rz_arm` (realize.bend:976-983)
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
