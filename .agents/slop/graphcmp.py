#!/usr/bin/env python3
"""graphcmp.py -- A CANONICAL GRAPH NORMAL FORM BOTH SIDES EMIT, AND A DIFFER OVER IT.

WHY THIS FILE IS NOT `diff <(pyrender) <(bend-pyrender)`.

A pretty diff over two graph printers compares the two PRINTERS, not the two graphs, and
the printers are not stable. Measured in `.agents/slop/pin-tree-oracle-report.md`, the
SAME logical node renders differently across upstream commits:

  * `CallInfo.__repr__` appends `, dtype=dtypes.int` at the pin and a later commit drops
    the clause (`tinygrad/uop/ops.py:1408`, plus the 18-row `uop/render` table).
  * `Ops.CUSTOM_FUNCTION`'s arg is a bare `str` at the pin and
    `CustomFunction(name='myfn', dtype=dtypes.void)` two commits later.
  * `UOp.range(4, AxisType.WEAK, 0, 1)` against `UOp(Ops.RANGE, (c1,), (AxisType.WEAK,
    0, 1))` -- the same node, two spellings.
  * `dtypes.float` / `dtypes.int` against `dtypes.f32` / `dtypes.i32`.

So a raw textual diff answers "which tinygrad commit is this?" -- twice -- and not
"does the port build the same graph?". That distinction IS the task. The deliverable is a
normal form both sides emit, and a diff over THAT.

THE COMPARABILITY TRAPS THIS FILE IS BUILT AGAINST. Each has produced a clean false zero
somewhere in this repo, and each is answered by construction rather than by care:

  1. ROW NAMES WITH SPACES. `PTX tensor_cores sm_75` is a real row name here.
     `^(\\S+) = ` drops it; the pin/HEAD study records that regex finding 12 shared rows
     where there were 228. -> the wire format is `<bytecount>:<bytes>` chunks and the
     reader WALKS THE COUNTS, so whitespace is never structural.
  2. LANE-SPECIFIC ROW SHAPES. Some lanes emit `name=value`, others `name = [value]`. A
     parser requiring `\\s=\\s` matches nothing and reports a clean zero. -> one reader
     here, and it accepts exactly one shape.
  3. LOCALE SORTING. A locale-colated `sort`/`comm` fabricates diffs, including on a no-op
     control. -> `LC_ALL=C` in every child's environment, Python's own `sorted()` in
     process, and `control`, which asserts the differ is quiet on a side against ITSELF.
  4. ZERO ROWS IS INDISTINGUISHABLE FROM "NOT STARTED". `bend` stack-overflows on roughly
     1 run in 20 and prints nothing. -> `emit_bend` RE-RUNS on an empty stream (5 tries)
     and then RAISES. A 0-row side is a FAILURE, never a verdict.
  5. UCache IDENTITY IS NOT STRUCTURAL IDENTITY. `tinygrad/uop/ops.py:201` keys on
     `(op, src, arg, tag, type(arg))`, so `(WEAK, 0, 1)` and `(WEAK, (0,1))` are
     DIFFERENT nodes with the same `str(arg)`. -> `depth` is its own FIELD (R5).
  6. `--check-only` EXITS 1 EVEN ON A CLEAN FILE (dtype.bend's 14 permanently-red laws).
     -> nothing here gates on bend's exit status; the stream is the evidence.
  7. `PYTHONPATH` CONTAMINATES CONTROLS. -> every child runs with `PYTHONPATH` REMOVED, and
     the tree is reported from `tinygrad.__file__` rather than assumed. (It is an editable
     install, so `import tinygrad` resolves from any cwd and `PYTHONPATH` is not a
     blocker -- confirmed by the pin/HEAD study's import log.)

THE NORMAL FORM. One record per node, eight fields, in this order:

    id  op  dtype  shape  depth  tag  arg  src

  R1  id      the emitting side's own arena index. REPORTING ONLY -- never identity. The
              two arenas number differently (CPython interns in ucache-hit order,
              ops.bend:1162 numbers by construction order), so a differ keyed on id
              compares nothing. Identity is the `core` key below.
  R2  op      `Ops.name` -- the BARE member name (`ADD`, not `Ops.ADD`). `Ops.__str__` is
              `Enum.__str__`, so CPython has two spellings per member (`str(op)` and
              `op.name`) and ops.bend:284-288 records that getting this wrong was a real
              port bug. The bare one serves `AxisType` too (ops.bend:662), so ONE
              spelling covers both enums.
  R3  dtype   `DType.name` -- `f32`, never `dtypes.f32` and never `float`.
              `DType.__repr__` is `f"dtypes.{self.name}"` (tinygrad/dtype.py:67) and `name`
              is the bare member. The normal form drops the decorator because the
              decorator is the thing that moved between commits.
  R4  shape   `UOp.shape` (ops.py:454-456); the literal `R` when it raises; the literal `N`
              when `_shape` is None (the ten ops at ops.py:331-338). Three-valued, because
              "has no shape" and "shape raised" are different facts. A dim is a `sint`
              (ops.py:1925) = `int|UOp`: an int prints as its EXACT `hi:lo` I64
              (`H.i64_text`, helpers.bend:1696-1699, is two words for exactly this) and a UOp
              prints as `U`. Never as a number -- a symbolic dim read as 0 is a silent
              wrong shape.
  R5  depth   how many times a RANGE arg's `axis_id` is NESTED. `UOp.range` builds
              `arg=(axis_type, axis_id)` (ops.py:643) with `axis_id` either an int or a
              tuple, and `axis_id` is `self.arg[1:]` (ops.py:498-500). So `(WEAK,0,1)` and
              `(WEAK,(0,1))` share a `str(arg)` and differ as ucache keys (ops.py:201
              includes `type(arg)`). The port carries the count as `Arena.shp`
              (ops.bend:1092-1100). Without this field the differ calls two different
              graphs equal.
  R6  tag     `UOp.tagstr` is `f", tag={self.tag}"` (ops.py:277) -- a repr of an `Any` that
              may be a bool, a str, an int or a tuple of UOps. Structured, never repr'd;
              absent is `N` because `tag is not None` is upstream's own test.
  R7  arg     the STRUCTURAL form: a recursive type-tagged encoding, NOT
              `UOp.argstr()`. Three reasons, all measured:
                * `argstr` is `repr(self.arg)` (ops.py:274-276), and `ParamArg.__repr__`
                  (ops.py:43-50) OMITS every field equal to its default and rewrites
                  `buffer` as `UOp.new_buffer(...).buffer` -- a device object no second
                  process can rebuild. A form that omits defaults cannot see a default
                  change; a form that prints a device object can never match.
                * so `ParamArg` is ALL THIRTEEN fields, in DECLARATION order (ops.py:
                  26-42), by NAME. `pyrender` itself refuses a BUFFER carrying a device
                  Buffer (render.py:159-160), so `buffer` reduces to PRESENCE -- `z` or
                  `N`. It USED TO emit the Buffer's `repr`, i.e. a device object, which is
                  the one thing this rule exists to forbid, and the header then claimed the
                  slot was compared when MEASURED `Buffer` has no `slot` at all. See
                  `paramarg`.
                * a `bytes` arg is the FULL byte list, MEASURED 2026-10-04 against the
                  port: `ABlob{bs: List<&2, U32>}` (ops.bend:1062) HOLDS the bytes and
                  `eq_arg.ABlob` (:1801) compares them element-wise. It used to be the
                  LENGTH, on a reason ("the port cannot fill it") that was true when
                  written and is false now -- and the cost was measurable: `--plant
                  bytes` hangs `b"aaaa"` and `b"bbbb"` off the matmul and the length-only
                  column printed `arg=y4` for BOTH, so a graph differing only in blob
                  content scored identical.
                * `CallInfo` (ops.py:1400) is not even a dataclass -- a plain class whose
                  `__repr__` prints `id(self.grad_fxn)`, a per-process address
                  (ops.py:1408-1410). So it is field-by-field too, and a CALL's difference
                  is reported as a NAMED field.
               THE DEVICE FIELD is the one that used to need a DECLARED binding, and it
               no longer does. Upstream's `ParamArg.device` is a NAME, and the chain to it
               is FIVE hops, every position CALLED rather than read off a docstring.
               MEASURED: `Device['CPU'].device == 'CPU'`. The chain is
               `_Device.__getitem__` (device.py:29) -> `ix = self.canonicalize(ix)` (:30)
               -> `_canonicalize` (:26), which upper-cases the stem and strips a trailing
               `:0` -> `__get_canonicalized_item(ix)` (:32) -> `get_class`'s `cls(ix)`
               (:37 -- NOT :29, which is the `def` itself) -> `Compiled.__init__`'s
               `self.device, ... = device, ...` (:396). From there the NAME flows into the
               graph through `ParamArg(..., device=device, ...)`: uop/ops.py:855 for a
               BUFFER, :1211 for a PARAM. The port's arena carries an interned `U32` tag
               instead (LAWS/spec.bend:85-87)
               and THE PORT ALREADY HAS THE READER -- `uop/render.bend:360-364`, whose
               table at :361 is the one `schedule/__init__.bend:1095` ("tag 0 stands for
               CPU") and `schedule/memory.bend:998` (`cpu() = S.D1{0}`) write against. So
               graphcmp.bend CALLS that reader and emits the port's NAME, and the
               correspondence is DERIVED from the port's own table instead of typed at a
               prompt. `--dev-map` and the `t<tag>` atom are GONE: a declared binding that
               can be wrong is worse than a name that cannot.

THE LEDGER, and why it is printed on EVERY report.

  A construct the normal form renders lossily is a construct whose difference this file
  CANNOT see. Left alone that is the worst kind of gap, because an absent disagreement
  reads as an agreement. So each one is a LETTER -- `z` a realized buffer's presence, `y`
  a bytes length, `u` a UOp nested in an arg, `q` an applied option the port cannot
  resolve, `X!` a dead AxisType member, `BAD` the arena's bottom, `E` an enum outside the
  three it knows -- or a field-local marker, `?` for a shape the port's fold could not
  settle. Each is COUNTED on both sides of every report and the non-zero ones are called
  out in a `# RESIDUALS IN THIS RUN:` line ABOVE the verdict, so the ledger can never be
  mistaken for part of the agreement. `selfcheck` asserts each marker is a spelling the
  emitter can actually produce, and `.agents/slop/graphcmp-probe-optq.bend` calls the
  three emitters no graph reaches today, so their rows are MEASURED rather than 0 by
  assumption.

  The ledger is also what makes a `0/0` worth printing: it answers "did that path run?"
  for the refusals, which is the question a residual list otherwise never answers.

  One field is NOT countable and is NAMED rather than counted, because a count would be 0
  by construction and therefore a claim: `KernelInfo.estimates`, which `ops.bend` dropped
  (P5, `tinygrad.renderer`) and whose upstream value is None for every kernel the port can
  build.
  R8  src     the ORDERED child indices. Order, not a multiset: the differ must be able to
              see a commutative-child swap (`--plant srcswap`), and `UOp.key` (ops.py:269)
              concatenates `s.key` for `s in self.src` IN ORDER, so upstream's own node
              identity is order-sensitive.

THE IDENTITY KEY, and why it is not the whole record.

    core = sha256(op, depth, tag, structural-arg, ordered child cores)

This is `UOp.key` (ops.py:269) -- `sha256(str((op, dtype, arg)) + concat(child keys))` --
with `str(arg)` replaced by R7 and with `dtype` and `shape` REMOVED. Two deliberate
departures from upstream:

  * `str(arg)` -> structural arg. Upstream's key is stable only because the PRINTER is
    stable, which is the premise being rejected here.
  * `dtype`/`shape` out of `core` and COMPARED AS FIELDS instead. In identity, a one-dtype
    change would present as "a node on one side and not the other", and the report would
    have to say "these differ" where it could say "this node's dtype is f32 on one side
    and i32 on the other". `UOp.key`'s own comment (ops.py:199) says why dtype is in
    UPSTREAM's key -- a CONST's dtype is the type of its arg and `True == 1` as dict keys
    -- and keeping dtype a compared FIELD keeps that fact with strictly more information.

PAIRING, three rungs, so a difference is NAMED rather than counted:

  1  equal `core` -> SHARED node; every field is then compared and each disagreement is
     printed BY FIELD NAME.
  2  the leftovers, paired by `loose = (op, depth, tag, arg-with-dtype-erased, ordered
     child OPS)`. This is what catches a plant that changes only a dtype or only a shape:
     the node keeps a partner and the difference is reported as the `dtype`/`shape` field
     rather than as an unexplained node.
  3  still unpaired -> ONLY-<side>, printed IN FULL, so nothing is summarised away.

THE NINE GRAPHS, and their node counts are MEASURED by `diff` on every run rather than
written down here, because a denominator that lives in a comment rots. `--graph NAME` on
its own is the whole invocation: ONE command, no other arguments, ONE verdict line.

    matmul  (Tensor.empty(4,3) @ Tensor.empty(3,5)).uop         18 nodes
    reduce  Tensor.empty(4,8).sum(axis=1).uop                    7
    buffer  Tensor.empty(4,3).realize().uop                      5   the `z` residual
    sink    UOp(Ops.SINK, (UOp.const(4),), KernelInfo())         2   `kI` + `R` shape
    range   UOp.range(4, (0, 1))                                2   THE ONLY NON-ZERO depth
    rangeflat UOp.range(4, 0)                                   2   the depth-0 twin
    cast    Tensor.empty(4,3).cast(dtypes.half).uop             6   a bare DType arg
    special UOp.special(4, "inf")                               2   a bare str arg
    binblob UOp(Ops.BINARY, (matmul,), b"tiny")                19   the `y` residual

`range` and `rangeflat` are a PAIR and exist together. Before them EVERY node in EVERY
graph had `depth=i0` on both sides, so R5 was a field that had never been asked a
question -- and when the first RANGE arrived it turned out to be OFF BY ONE on the py
side (see `cdepth`). A field that reads equal because both sides are wrong is worse than
a field that is not compared, and only a graph that reaches the field finds that.

USAGE

    python3 .agents/slop/graphcmp.py selfcheck
    python3 .agents/slop/graphcmp.py emit py   --graph matmul  > runs/graphcmp/py.txt
    python3 .agents/slop/graphcmp.py emit bend                  > runs/graphcmp/bend.txt
    python3 .agents/slop/graphcmp.py diff --graph matmul
    python3 .agents/slop/graphcmp.py diff --plant srcswap       # ORDERED: names `src`
    python3 .agents/slop/graphcmp.py diff --plant srcswap --equiv   # EQUIV: AGREE
    python3 .agents/slop/graphcmp.py control
    python3 .agents/slop/graphcmp.py conf        # the three conflations, one line each
    python3 .agents/slop/graphcmp.py dbg --levels 0,1,2   # across DEBUG, graph held fixed

There is no `--dev-map`. The device name is not bound at a prompt: the port resolves its
interned tag through its own table (R7) and both sides then carry a NAME. There is no
`--plant-side` either: it was ACCEPTED AND NEVER READ, which is the same defect as the
`--graph` default this file was already measured to have, so it is gone rather than
documented. Planting the bend side would mean writing six DAG rewrites in Bend against a
graph the port builds node for node -- a second implementation of the tree, not a plant.

Exit status: 0 when the two sides agree on every core and every field, 1 when they do not,
2 when the comparison was NOT WELL-POSED or a side produced nothing -- which is a FAILURE
and never a verdict (trap 4 above).
"""
from __future__ import annotations

import argparse
import enum
import hashlib
import os
import pathlib
import subprocess
import sys

# The commutative op set, filled from CPython by `commutative()` once tinygrad is
# imported. It is a module global because `Node.key` is a method and threading it
# through every node would be noise; `selfcheck` asserts it is non-empty, so a
# run that forgot to fill it fails loudly rather than making `--equiv` the identity.
COMM: frozenset = frozenset()

REPO = pathlib.Path(__file__).resolve().parents[2]
SLOP = REPO / ".agents" / "slop"
BEND_PROBE = SLOP / "graphcmp.bend"
BEND_DBG = SLOP / "graphcmp-dbg.bend"
BEND = REPO / "bin" / "bend"

# `tinygrad.helpers.DEV` is resolved when tinygrad is IMPORTED, so `--dev` has to be decided
# before the import or the py side quietly builds its graph on whatever device opens first
# (METAL here). MEASURED both ways: `os.environ["DEV"]="CPU"` before `from tinygrad import
# Tensor` gives `Device.DEFAULT == "CPU"`; the same assignment after it leaves `METAL`.
# `from __future__ import annotations` is above, so every tinygrad name here is used only in
# a body or a never-evaluated annotation and the import can be deferred to `load`.
def load_tinygrad() -> None:
  import tinygrad.dtype as dtm
  import tinygrad.uop.ops as opm
  from tinygrad.uop import GroupOp
  globals().update(AddrSpace=dtm.AddrSpace, DType=dtm.DType, dtypes=dtm.dtypes,
                   AxisType=opm.AxisType, Ops=opm.Ops, ParamArg=opm.ParamArg, UOp=opm.UOp,
                   GroupOp=GroupOp)


def commutative() -> frozenset:
  """The ops whose CHILD ORDER carries no meaning, READ FROM CPython rather than typed.
  MEASURED both sides on 2026-10-04 and they agree on all eight:
    CPython `GroupOp.Commutative` (tinygrad/uop/__init__.py:121)
      = ADD AND CMPEQ CMPNE MAX MUL OR XOR
    the port's `GroupOp.commutative` (ops.bend:521-530)
      = ADD MUL MAX CMPNE CMPEQ XOR AND OR
  Typing the list into the harness would be a second place for it to be wrong, and two
  copies of an op classification disagreeing is exactly the class of defect this file
  exists to find -- so the harness asks CPython. `selfcheck` asserts the answer is
  non-empty, because an empty one would make `--equiv` silently the identity and print
  AGREE for everything, which is the shape of the failure this whole file is about."""
  return frozenset(o.name for o in GroupOp.Commutative)


# THE ATOM TABLE. One letter per value KIND and no letter reused, because a collision
# would make two different values render the same and a differ would then agree with
# itself for the wrong reason -- `selfcheck` asserts the distinctness.
#
# `z` and `q` and `u` are the three REFUSALS, added 2026-10-03, one letter each:
#   z  a realized BUFFER's device object is PRESENT. Nothing about it is compared but
#      its presence. MEASURED: `Buffer` has no `slot`, so there is no name for it on
#      this side, and the port's `Maybe<&2,U32>` is a P6 allocator slot with no runtime
#      behind it (ops.bend:913 is the same note for bytes). The ABSENT case keeps the
#      older spelling `unrealized` rather than `N` for one measured reason and not for
#      taste: `unrealized` CONTAINS `realized` as a substring, so any substring scan
#      over an arg counts the absent case as a present one. Measured by writing the scan
#      that way first and getting the wrong answer.
#   u  a UOp nested inside an `arg`. Both sides emit it; neither compares identity.
#   q  an APPLIED OPTION the port cannot resolve (see R7's KernelInfo note).
ATOMS = {"none": "N", "u32": "i", "i64": "l", "float": "f", "bool": "b", "str": "s",
         "bytes": "y", "dtype": "D", "ops": "O", "axis": "X", "addr": "S", "invalid": "v",
         "buf": "z", "uop": "u", "opt": "q", "enum": "E"}

# THE COMPOSITE ARG FORMS, and their PREFIXES, enumerated because nothing else enumerates
# them and a census that reports them as unmapped values is reporting a category error.
# MEASURED: `carg`'s per-op arms here and `argstr`'s arms in graphcmp.bend spell exactly
# these ten two-or-more-character openers, and each is a NESTED grammar -- the inside is the
# ordinary atom grammar. `P(` is `ParamArg`'s thirteen fields in declaration order.
# Without this list a coverage census reads `r` and `k` out of `rd(OADD,i1)` and `rg(i1,..)`
# and calls them unmapped ATOMS, which they are not: they are structure, and the atoms are
# the `O` and the `i` inside.
COMPOSITE = ("P(", "al(", "cF(", "cI(", "in(", "kI(", "pI(", "rd(", "rg(", "wm(")


def chunk(s: str) -> str:
  """`<bytecount>:<bytes>` -- BYTES, because bytes are what the reader walks."""
  b = s.encode()
  if any(c > 127 for c in b):
    raise ValueError(f"non-ASCII in a normal-form chunk: {s!r}")
  return f"{len(b)}:{b.decode()}"


def unchunks(line: str) -> list[str]:
  """Walk the counts. Splitting on whitespace is what dropped 216 of 228 rows in the
  pin/HEAD study, because the row NAMES contain spaces.

  THE SEPARATOR IS OPTIONAL AND THAT IS A FIX, not a loosening. MEASURED 2026-10-04: the
  reader used to REQUIRE a single space after every chunk, so it made whitespace
  structural -- the one thing the `<bytecount>:<bytes>` format exists to avoid. Nothing
  caught it because every field the eight-field wire carried was an ATOM text, and no atom
  contains a space. The DEBUG rows broke it: a site prints `memory reduced from 0.01 MB ->
  0.01 MB, 5 -> 2 bufs`, so the `arg` chunk contains spaces and the reader walked off the
  end of the first chunk and then REFUSED the line, which surfaced as "0 trace rows" -- a
  reader returning fewer rows than the emitter wrote, reported as a count rather than as a
  failure. The counts are authoritative, so the reader now steps over AT MOST one space and
  does not insist on one. It cannot lose information: every chunk's length is stated."""
  out, i = [], 0
  while i < len(line):
    j = line.index(":", i)
    n, k = int(line[i:j]), j + 1
    out.append(line[k:k + n])
    i = k + n
    if i < len(line) and line[i] == " ":
      i += 1
  return out


def u(x: int) -> str:
  return ATOMS["u32"] + str(x)


def i64(x: int) -> str:
  """`hi:lo` in DECIMAL, exactly `H.i64_text` = `i64_show(hi32, lo32)` = `U32.show(hi) ":"
  U32.show(lo)` (helpers.bend:1696-1699). A dim is an I64, and dropping the high word would
  read a dimension of 2**32 as zero."""
  return ATOMS["i64"] + f"{x >> 32}:{x & 0xFFFFFFFF}"


def tup(xs) -> str:
  return "n(" + ",".join(xs) + ")"


def bstr(s: str) -> str:
  return ATOMS["str"] + s


def bo(x) -> str:
  return ATOMS["bool"] + ("1" if x else "0")


# The `N` arm of `cshape`, counted. See that function: it is dead by measurement and this
# counter is what keeps the measurement honest across future edits.
SHAPE_NONE_HITS = 0


def dt(d: DType) -> str:
  return ATOMS["dtype"] + d.name


def dev(x) -> str:
  """`ParamArg.device` is `str|tuple[str, ...]|None` (ops.py:33) and both spellings are
  NAMES: `Compiled.device` is the canonicalized device string (device.py:396/:29/:26).
  graphcmp.bend emits the port's name for the same device, resolved through
  `uop/render.bend:363`, so there is nothing to bind and nothing to declare here."""
  if x is None:
    return ATOMS["none"]
  return ATOMS["str"] + ",".join(x) if isinstance(x, tuple) else bstr(str(x))


def konst(x) -> str:
  """`Ops.CONST`'s arg is a bare `PyConst` (`int|float|bool|bytes|Invalid`, ops.py:122) and
  the port spells the same thing `Const` (ops.bend:807-811). CPython's int is normalised to
  the port's I64 form so `UOp.const(4)` is `l0:4` on BOTH sides rather than `i4` here and
  `l0:4` there."""
  if isinstance(x, bool):
    return bo(x)
  if isinstance(x, int):
    return i64(x)
  if isinstance(x, float):
    return ATOMS["float"] + repr(x)
  if isinstance(x, bytes):
    # LENGTH only, and so does the port (ops.bend:913: "bytes BINARY arg; only its length
    # is read"). Comparing the content would be a field the port can never fill, and
    # comparing the length is a real comparison both sides can make.
    return ATOMS["bytes"] + str(len(x))
  return ATOMS["invalid"] if type(x).__name__ == "Invalid" else f"raw({type(x).__name__})"


# THE ARG TAXONOMY, BY OP. ops.bend:892-921 lists the nineteen things `arg: Any` can hold
# and the op each belongs to; the same table is what makes the two sides' texts the same
# TEXT and not merely two structurally-similar ones. Only the ops whose CPython value is
# SHAPED differently from the port's typed record need a case -- CAST's DType and PERMUTE's
# tuple already render identically through `_carg`.
def carg(op: Ops, x) -> str:
  """R7, CPython side. Mirrors `argstr` in graphcmp.bend character for character."""
  if op is Ops.CONST:
    return konst(x)
  if op is Ops.RANGE:
    # `depth` first, then the axis type, then the FLATTENED id tail. The flattening is
    # `flat()`'s job and the reason is in `cdepth`: the port holds the tail as a flat
    # `List<U32>` plus a DEPTH, so `flat(axis_id)` + `depth` is the only rendering both
    # sides can produce, and the old `str(tuple)`-inside-a-`u32` spelling was a repr
    # wearing a structural field's clothes.
    return f"rg({u(argdepth(x))},{ATOMS['axis']}{x[0].name},{tup([u(i) for i in flat(x[1])])})"
  if op is Ops.REDUCE:
    return f"rd({ATOMS['ops']}{x[0].name},{u(x[1])})"
  if op is Ops.WMMA:
    dims, dtp, thr, tc = x
    return (f"wm({tup([u(i) for i in dims])},{dt(dtp)},{u(thr)},"
            + (tup([u(i) for i in tc]) if tc is not None else ATOMS["none"]) + ")")
  if op is Ops.INS:
    return f"in({bstr(x[0])},{dt(x[1])})"
  if op is Ops.ALLREDUCE:
    return f"al({ATOMS['ops']}{x[0].name},{dev(x[1])})"
  if op is Ops.CUSTOM_FUNCTION:
    return f"cF({bstr(x.name)},{dt(x.dtype)})"
  if op is Ops.CALL:
    # CPython's CallInfo (ops.py:1400-1410) is a PLAIN CLASS with five class-level
    # attributes; `grad_fxn` is dropped because its own repr prints `id(...)` (ops.py:1409),
    # a per-process address, and `aux` is dropped because it is `Any`. The port has four
    # fields including a `dtype` CPython does not have (ops.bend:1059-1060), so the two
    # TEXTS differ on purpose: a CALL node is reported as a named `arg` difference rather
    # than smoothed into an agreement.
    return "cI(" + ",".join([bstr(x.name) if x.name is not None else ATOMS["none"],
                             bo(x.precompile), bo(x.precompile_backward)]) + ")"
  if op is Ops.SINK:
    # FOUR SLOTS, and the arity is the point. It was three, and the port's emitter wrote
    # TWO (`kI(<name>,<beam>)`, graphcmp.bend), so the texts could not agree for any
    # reason other than "the port renders fewer fields" -- which a differ reports as a
    # disagreement about the graph. The four are `KernelInfo`'s own fields in DECLARATION
    # order (ops.py:1342-1347), minus `estimates`:
    #   * `name`, `beam` -- compared outright.
    #   * `applied_opts` -- the port types it `List<&2,U32>` (ops.bend:978) and upstream's
    #     elements are `Opt` dataclasses (`Opt(op=OptOps.TC, axis=0, arg=4)`). Those are
    #     not comparable and pretending otherwise is the "copy the port's answer into the
    #     oracle" move, so the PORT emits one `q` per option: the COUNT still compares and
    #     the content is a named refusal. MEASURED, and this is why the count is worth
    #     keeping: the port's own `KernelInfo.of()` has `applied_opts = Nil{}` and
    #     `opts_to_apply = None` (probe `pb-buf-binary.bend`, Q1b), and no port file ever
    #     writes a non-empty one -- `render.bend:655` calls those U32s "UOp INDICES", and
    #     that reading is UNVERIFIED, because there is no construction site to verify it
    #     against. So the port cannot fill them and must not pretend to.
    #   * `opts_to_apply` -- it was DROPPED ON BOTH SIDES, which is the residual nobody was
    #     looking at: `KernelInfo` (ops.py:1345) declares it, upstream writes it on every
    #     `llm/kernels/amd.py` and `nn/__init__.py` SINK as `opts_to_apply=()` -- an EMPTY
    #     TUPLE, which is not `None` -- and the port's field is `None` (measured, Q1b).
    #     So the two sides genuinely differ here, on every SINK those files build, and
    #     until now this gate could not see that in either direction.
    #   `estimates: Estimates|None` is not ported (P5, `tinygrad.renderer`) and upstream's
    #   value is None for every kernel the port can build; `render.bend:653` pins it to the
    #   literal `estimates=None` for the same reason. It is not a fourth-vs-fifth slot: a
    #   field neither side carries cannot be compared by either, and the ledger below is
    #   where "not carried" is stated.
    return f"kI({bstr(x.name)},{tup([_carg(o) for o in x.applied_opts])},{_carg(x.opts_to_apply)},{u(x.beam)})"
  if op is Ops.PROGRAM:
    # `ProgramInfo.global_size` is `tuple[int|float, ...]` (ops.bend:1352); the port holds
    # `H.I64` and the float case is a `sint`'s, recorded on `sint_of` there. CPython's
    # floats are rendered as `f<value>` so a float size is visible rather than truncated.
    return "pI(" + ",".join([_carg(x.global_size), _carg(x.local_size), _carg(x.vars),
                             _carg(x.globals), _carg(x.outs), _carg(x.ins)]) + ")"
  return _carg(x)


def _carg(x) -> str:
  """The generic value grammar: one letter per kind, no letter reused, and a NAMED `raw`
  for anything unmapped. A fallback that printed `repr` here would reintroduce the whole
  problem this file exists to remove.

  THE ENUM ARM IS NOT COSMETIC, and the reason is not the one first written down here.
  Before it, `enum.Enum` fell through to the `vars()` arm below and MEASURED
  `carg(Ops.SINK, <a KernelInfo with a non-empty applied_opts>)` DIED with
  `TypeError: vars() argument must have __dict__ attribute`, so a kernelized graph could
  not be emitted at all and the residual was written up as "an `Opt` dataclass the port
  cannot read" when the honest answer was "this emitter raises".

  THE ACTUAL CHAIN, because the obvious explanation is wrong and cost a probe
  (`runs/graphcmp/probe/p12-residual-evidence.py`). It is NOT that an enum member lacks
  `__dict__` -- MEASURED, `vars(OptOps.TC)` returns a real `dict` with four entries and
  three of them (`_value_` 1, `_name_` "TC", `_sort_order_` 0) render perfectly as
  `i1`/`sTC`/`i0` through the arms above. The fourth, `__objclass__`, is THE ENUM CLASS.
  `vars()` on a class returns its `mappingproxy` (17 entries for `OptOps`), the loop walks
  that namespace, and MEASURED the first entry that reaches the `vars()` arm and is not a
  class is `_new_member_`, a `builtin_function_or_method`, which has no `__dict__` --
  `TypeError`. (`_member_map_`, a `dict`, is the second.) So the defect was never "enums
  are special": it was that **the generic `vars()` fallback FOLLOWS `__objclass__` out of
  the value and into its class**, and had it survived it would have emitted a text full of
  dunder names and a recursive walk back through `OptOps.TC` -- the printer instability
  this whole file exists to remove, arriving through the back door.

  Two independent guards, and both are load-bearing: the enum arm stops the walk at the
  value, and the `__dict__ is None` guard at the bottom catches the descriptors had the
  arm not existed. `Ops`, `AxisType` and `AddrSpace` are matched by exact type above, so
  this arm is the one that catches `OptOps` (codegen/opt/__init__.py:6) and anything a
  later commit adds. The member's `name` is its identity -- `list(OptOps)` is
  TC/SPLIT/PADTO/SWAP and `name` is unique per member -- so `name` is what is compared and
  `value` is not."""
  if x is None:
    return ATOMS["none"]
  if isinstance(x, DType):
    return dt(x)
  if isinstance(x, Ops):
    return ATOMS["ops"] + x.name
  if isinstance(x, AxisType):
    return ATOMS["axis"] + x.name
  if isinstance(x, AddrSpace):
    return ATOMS["addr"] + x.name
  if isinstance(x, enum.Enum):
    return ATOMS["enum"] + f"{type(x).__name__}.{x.name}"
  if isinstance(x, bool):
    return bo(x)
  if isinstance(x, int):
    return u(x)
  if isinstance(x, float):
    return ATOMS["float"] + repr(x)
  if isinstance(x, str):
    return bstr(x)
  if isinstance(x, bytes):
    # CONTENT, and this is a WIDENING rather than a retune. It used to be
    # `ATOMS["bytes"] + str(len(x))`, on the stated reason that "the port cannot fill
    # it" -- a reason that was TRUE when this line was written and is FALSE now.
    # MEASURED 2026-10-04 in `tinybendygrad/uop/ops.bend`: `ABlob{bs: List<&2, U32>}`
    # (:1062) holds the BYTES, not the length -- the header at :1793 records the change
    # and why ("`ABlob{n: U32}` -- the LENGTH -- and two different same-length blobs were
    # then the same node"), and `eq_arg.ABlob` (:1801) compares `bs` element-wise. So the
    # port CAN now tell `b"aaaa"` from `b"bbbb"` and a length-only column was refusing a
    # comparison the port is able to make.
    #
    # WHAT IT COST TO LEAVE IT, measured on `--plant bytes`, which hangs `b"aaaa"` and
    # `b"bbbb"` off the matmul: the two differ upstream (different ucache keys,
    # ops.py:201) and this column printed `arg=y4` for BOTH, so a graph differing only in
    # blob content scored identical. Two same-length blobs are now two different `arg`
    # texts and the differ names them.
    #
    # WHAT IS STILL NOT COMPARABLE, and is now the whole of the `y` residual: a bytes
    # CONST. Upstream's `PyConst` includes `bytes` (ops.py:122) and the port's `Const`
    # does NOT -- `ops.bend:810-811` is `CBool{} | CInt{} | CFloat{} | CInvalid{}` and
    # graphcmp.bend's `konst` has no bytes arm, so there is no port spelling at all.
    return ATOMS["bytes"] + " n(" + ",".join(u(b) for b in x) + ")"
  if isinstance(x, (tuple, list)):
    return tup([_carg(e) for e in x])
  if isinstance(x, UOp):
    # An ARG may hold a UOp: `Ops.PYLITERAL`'s literal and `Ops.MSELECT`'s matcher
    # (ops.bend:907-911). This was `ATOMS["str"] + "<uop>"`, which is a STRING atom --
    # so a PYLITERAL holding a UOp was indistinguishable from a PYLITERAL holding the
    # five-character string `<uop>`, and `selfcheck`'s distinctness claim did not cover
    # it because both sides made the same substitution. It is its own letter now.
    #
    # THE JUSTIFICATION THE OLD COMMENT GAVE WAS FALSE, and measuring it is the reason
    # this is a refusal rather than a fix. The comment said "the arg's identity is
    # already carried by the graph's `src` edges". MEASURED, calling CPython:
    #   `p = UOp(Ops.PYLITERAL, (), (UOp.const(4),))`  ->  `len(p.src) == 0` and
    #   `p.toposort() == [p]` -- the nested UOp is in NEITHER. So it has no index in the
    #   toposort this file numbers arenas by, and there is no arena index to compare. The
    #   port's only carriers are `ATuple`/`TTuple` of U32, and `ATuple` also serves
    #   PERMUTE, where the U32s are LITERAL ints (graphcmp.bend's own matmul builds
    #   `O.ATuple{[0, 2, 1]}` for PERMUTE), so the two readings cannot be told apart from
    #   the value. Hence: both sides emit `u`, the ledger counts it, and `--plant pyuop`
    #   shows the resulting node as one-sided rather than as agreement.
    return ATOMS["uop"]
  if isinstance(x, ParamArg):
    return paramarg(x)
  if type(x).__name__ == "Invalid":      # dtype.py:32; a CONST holding one is a refusal
    return ATOMS["invalid"]
  if hasattr(x, "__dataclass_fields__"):
    return f"{type(x).__name__}(" + "".join(
      f"{n}={_carg(getattr(x, n))}" for n in x.__dataclass_fields__) + ")"
  d = getattr(x, "__dict__", None)
  # `None` here is an object with no instance dict -- a slot-only class, a C type. The
  # old `vars(x)` raised on those (the enum case above, reached first now); `raw` is the
  # NAMED refusal the grammar promises, and it is visibly a refusal rather than a value.
  if d is None:
    return f"raw({type(x).__name__})"
  return f"{type(x).__name__}(" + "".join(
    f"{k}={_carg(v)}" for k, v in d.items() if k != "grad_fxn") + ")"


def paramarg(pa: ParamArg) -> str:
  # Field 11 (`buffer`) is PRESENCE and nothing else, and that is a CHANGE, not a
  # restatement. It used to be `f"realized{u(pa.buffer)}"`, which is `"realized" + "i" +
  # str(<Buffer>)` -- MEASURED on `Tensor.empty(4,3).realize().uop`:
  #     P(i1,Df32,i12,N,N,N,SGLOBAL,sCPU,b0,N,
  #       realizedi<buf real:False device:CPU size:12 dtype:dtypes.f32>,b0,N)
  # so the normal form carried a DEVICE OBJECT REPR, which is the one thing R7 exists to
  # forbid, and the header claimed otherwise. That repr embeds `dtypes.f32` (the token
  # that moves between upstream commits, R3) and `real:<bool>` (an allocation state), and
  # `Buffer` has no `slot` attribute at all -- MEASURED -- so there was never a slot
  # there to compare. Everything about a Buffer that IS stable and IS meaningful --
  # `size`, `dtype`, `device`, `offset` -- is ALREADY one of ParamArg's own thirteen
  # fields and is already compared above, so presence is the finest split the two sides
  # can both make. `trace_num` is a per-process counter and is never read.
  #
  # `N` FOR ABSENCE, and this is a TEXT change from the `unrealized` it replaces -- on
  # both sides, so the comparison is untouched. Two reasons, both measured. `unrealized`
  # CONTAINS `realized` as a substring, so any substring scan over an arg counts the
  # absent case as a present one. And it starts with the ledger's `u`, so at a value
  # position -- which is exactly where it sits -- `at_value` counts a nested UOp that is
  # not there. `selfcheck` asserts the collision is gone. The uniform `N` is also what
  # the other six `Maybe` fields of this same record already render, so the record has
  # ONE spelling for absence instead of two.
  return "P(" + ",".join([
    u(pa.slot), dt(pa.dtype),
    u(pa.size) if pa.size is not None else ATOMS["none"],
    "r(" + i64(pa.vmin_vmax[0]) + "," + i64(pa.vmin_vmax[1]) + ")" if pa.vmin_vmax is not None else ATOMS["none"],
    u(pa.multiple_of) if pa.multiple_of is not None else ATOMS["none"],
    bstr(pa.name) if pa.name is not None else ATOMS["none"],
    ATOMS["addr"] + (pa.addrspace.name if pa.addrspace is not None else "None"),
    dev(pa.device),
    bo(pa.volatile),
    "n(" + u(pa.image[0]) + "," + u(pa.image[1]) + ")" if pa.image is not None else ATOMS["none"],
    ATOMS["buf"] if pa.buffer is not None else ATOMS["none"],
    bo(pa.bind_on_realize),
    _carg(pa.val)]) + ")"


def cshape(n: UOp) -> str:
  """R4. Three values, and MEASURED 2026-10-03: one of them is DEAD on this side.
  `UOp.shape` is a property that raises IFF `_shape is None` (ops.py:455), so it NEVER
  RETURNS `None` and the `N` arm below cannot fire. Probed over every op in the upstream
  no-shape list (IF BARRIER SINK REWRITE_ERROR ENDIF BACKEDGE GROUP LINEAR PROGRAM SOURCE,
  ops.py:331-338) plus a void `INS` and a `PYLITERAL`: in all twelve, `_shape is None` AND
  `shape` raises (`runs/graphcmp/probe/p9-shape-none.py`).

  The arm is KEPT and counted rather than deleted, because a deleted branch is a claim and
  a counter is a measurement: `SHAPE_NONE_HITS` is printed on every report, so "this never
  fires" is asserted by the run that says so instead of by a comment that can rot.

  THE COLLISION THIS EXPOSED, which is the finding and not the fix. The bend side spells
  "the op has no shape" as `N`, so the two sides were using ONE letter for TWO different
  facts and only the py side's copy was unreachable. It stayed invisible until a graph
  with a shape-less node existed: `--graph sink` (added for this unit) is the first, and it
  reported `MISMATCH SINK py#2 vs bend#2 shape py=R bend=N` -- a rung-1 field mismatch on a
  node whose CORE MATCHED, which by this file's own measured theorem cannot mean the graphs
  differ. It means the two `_shape` implementations disagree, and here is which one is
  wrong: upstream's `shape` RAISES for every no-shape op, so the faithful rendering of
  "no shape" is `R` on both sides, and graphcmp.bend now emits `R` for its `Some{None}`.
  The port's OTHER no-Derived state (the fold produced nothing for this node) is a
  port-only fact with no upstream counterpart at all, and it gets its own atom, `?`, so a
  fold that stops settling cannot read as an agreement with a raise."""
  global SHAPE_NONE_HITS
  try:
    shp = n.shape
  except RuntimeError:
    return "R"
  if shp is None:
    SHAPE_NONE_HITS += 1
    return "N"
  return "(" + ",".join("U" if isinstance(d, UOp) else i64(d) for d in shp) + ")"


def flat(x) -> list:
  """Flatten nested int tuples into one list of ints. R5's axis-id tail is the ONE arg
  that nests (ops.py:643 `arg=(axis_type, axis_id)`), and the port cannot hold the
  nesting -- `ARange{ids: List<&2, U32>}` plus `Arena.shp`'s DEPTH is its whole
  representation (ops.bend:2500 "ARange stores the ints only", and :1097-1101). So the
  faithful common normal form for a RANGE arg is `flat(axis_id)` plus `depth`, which is
  exactly the pair the port stores and nothing either side has to invent.

  BEFORE this, the nested case was rendered by `str(tuple)` INSIDE a `u32` atom --
  `u((0,1))` is the six characters `i(0, 1)` -- which is Python's repr doing the work
  inside a structural field. MEASURED on the old spelling: `UOp.range(4, (0,1))` emitted
  `rg(i2,XWEAK,n(i(0, 1)))`, a shape the port cannot produce for any ids at all."""
  if isinstance(x, tuple):
    return [e for t in x for e in flat(t)]
  return [x]


def argdepth(x) -> int:
  """How many times a RANGE arg's `axis_id` -- `x[1]`, the second slot of `arg` -- is
  NESTED. Split out of `cdepth` because `carg` needs it too (R5 is in the `arg` text AND
  in its own field, deliberately, so a disagreement in either place is a disagreement)."""
  ids, k = x[1], 0
  while isinstance(ids, tuple):
    ids, k = ids[0], k + 1
  return k


def cdepth(n: UOp) -> int:
  """R5. Only a RANGE's `axis_id` can nest; `UOp.new` stores 0 for everything else.

  MEASURED 2026-10-04, and this was WRONG BY ONE until the first graph reached a RANGE.
  The old body walked `n.arg[1:]`, and `arg` is a 2-TUPLE, so `arg[1:]` is a tuple for
  EVERY RANGE -- it counts the tuple-ness of the ARG, not the nesting of `axis_id`, and
  the port's `Arena.depth` (ops.bend:1097-1101) counts the latter. MEASURED over four
  fixtures, calling CPython for both numbers:

      axis_id    graphcmp (old)   Arena.depth   u.arg
      0           1                 0             (AxisType.WEAK, 0)
      (0,)        2                 1             (AxisType.WEAK, (0,))
      (0, 1)      2                 1             (AxisType.WEAK, (0, 1))
      ((0, 1),)   3                 2             (AxisType.WEAK, ((0, 1),))

  Off by one on all four. It was invisible for a measured reason and not a lucky one:
  NO graph emitted before 2026-10-04 contained a RANGE, so `cdepth` returned 0 on the py
  side and `Arena.depth` returned 0 on the bend side and THE TWO ERRORS CANCELLED. A
  field that reads equal because both sides are wrong is worse than a field that is not
  compared, and the only thing that found it was adding a graph that reaches the field.
  The port's own header already had the right definition in prose ("0 = flat
  `(at, *ints)`; N>0 = `arg[1]` nested N times", ops.bend:1097) and this file did not
  match it. Now it does: `arg[1]`, walked while it is a tuple.
  """
  return argdepth(n.arg) if n.op is Ops.RANGE else 0


def ctag(t) -> str:
  return ATOMS["none"] if t is None else carg(t)


def row_of(n: UOp, k: int, ix: dict) -> str:
  return " ".join(chunk(v) for v in [u(k), n.op.name, n.dtype.name, cshape(n), u(cdepth(n)),
                                     ctag(n.tag), carg(n.op, n.arg), tup([u(ix[id(s)]) for s in n.src])])


# ---------------------------------------------------------------------------
# THE GRAPHS. Real, and LAZY (never realized), because a realized BUFFER carries a device
# `Buffer` the port cannot name.
def g_matmul():
  """`(Tensor.empty(4,3) @ Tensor.empty(3,5)).uop` -- 18 nodes of ALLOC, CONST, STACK,
  RESHAPE, PERMUTE, MUL and REDUCE, every one of which the port can build."""
  from tinygrad import Tensor
  return (Tensor.empty(4, 3) @ Tensor.empty(3, 5)).uop


def g_reduce():
  """`Tensor.empty(4,8).sum(axis=1).uop` -- a second real graph, and the one whose CONST
  seed is NOT weakint (a sum starts from `acc_dtype.const(0)`), which is R3's real test."""
  from tinygrad import Tensor
  return Tensor.empty(4, 8).sum(axis=1).uop


def g_buffer():
  """`Tensor.empty(4,3).realize().uop` -- MEASURED: five nodes, BUFFER CONST CONST STACK
  RESHAPE, the ALLOC having become a BUFFER. This is the graph that exercises `ParamArg`'s
  ELEVENTH field, which no lazy graph can carry, so the `z` atom is diffed for real rather
  than asserted in a comment. Its ParamArg is the same as the matmul's ALLOC except that
  `buffer` is a device `Buffer` instead of None.

  MEASURED, and it is why the fixture is not the matmul with one word changed:
  `Tensor.empty(4,3)` builds `ALLOC(ParamArg(slot=0, ..., bind_on_realize=True))` and
  `.realize()` replaces it with `BUFFER(ParamArg(slot=1, ..., buffer=<Buffer>,
  bind_on_realize=False))`. Realize MINTS A FRESH ParamArg -- `UOp.new_buffer`,
  ops.py:1208, `if slot is None: slot = next(UOp.unique_num)` -- so a realized buffer's
  slot is not the ALLOC's slot and its `bind_on_realize` is not the ALLOC's."""
  from tinygrad import Tensor
  t = Tensor.empty(4, 3)
  t.realize()
  return t.uop


def g_sink():
  """`UOp(Ops.SINK, (UOp.const(4),), KernelInfo())` -- the graph that exercises the SINK
  arg, and so the four-slot `kI(..)` and the `R` shape value (MEASURED: `UOp.shape` on a
  SINK raises `RuntimeError`, ops.py:455, so the shape column is `R` and not `N`). All
  five `KernelInfo` fields are at their defaults, which is the only value BOTH sides can
  produce: the port's `KernelInfo.of()` is `{"test", Nil{}, None{}, 0}` and no port file
  ever writes a non-empty option list."""
  from tinygrad.uop.ops import KernelInfo, UOp
  return UOp(Ops.SINK, (UOp.const(4),), KernelInfo())


def g_range():
  """`UOp.range(4, (0, 1))` -- 2 nodes, and the FIRST graph whose `depth` field is
  non-zero on EITHER side. MEASURED, calling CPython: `cdepth` is 1 and `u.arg` is
  `(AxisType.WEAK, (0, 1))`. Every graph above reads `depth=i0` on both sides, so R5 was
  a field that had never been asked a question."""
  return UOp.range(4, (0, 1))


def g_rangeflat():
  """`UOp.range(4, 0)` -- 2 nodes, `depth` 0, the flat reading. It exists to be
  COMPARED WITH `g_range` (`cross`): same op, same dtype, same `()` shape, same `N` tag,
  and the pair differs in exactly two of the eight fields -- `depth` and `arg`."""
  return UOp.range(4, 0)


def g_cast():
  """`Tensor.empty(4,3).cast(dtypes.half).uop` -- 6 nodes. MEASURED, calling CPython: the
  new node is a `CAST` whose arg is a BARE `DType` (`Df16`), which is the `ADt` arm of
  the arg taxonomy. No graph before this one emitted a `DType` as a WHOLE arg -- every
  `D<name>` was a `ParamArg` FIELD -- so `carg`'s `isinstance(x, DType)` arm had no
  fixture, and neither did graphcmp.bend's `case O.ADt{ad}`. The second dtype in the
  graph also makes R3's `name` (`f16`, not `float`) load-bearing rather than uniform."""
  from tinygrad import Tensor
  return Tensor.empty(4, 3).cast(dtypes.half).uop


def g_special():
  """`UOp.special(4, "inf")` -- 2 nodes, and the `AStr` arm on a node that is not a
  `SINK`. MEASURED: the arg is `sinf`, so a bare string atom is separated from
  `KernelInfo.name`'s use of one (which sits inside `kI(..)`)."""
  return UOp.special(4, "inf")


def g_binblob():
  """`UOp(Ops.BINARY, (matmul,), b"tiny")` -- 19 nodes, and the graph that makes the `y`
  residual LIVE instead of 0. Four graphs shipped with the `bytes` ledger row reading
  `py=0 bend=0`, which is a fact about the fixture and not about the port. This fixture
  carries a blob. MEASURED, calling CPython: the BINARY's shape is `(4,)` -- `ops.py:365`
  `case Ops.BINARY: return (len(self.arg),)` -- its dtype is `u8` and its arg is `y4`.

  It is BINARY UNDER the matmul rather than beside it, so the denominator is 19 nodes and
  not 1: `AGREE` on one node is not a claim.

  `base("matmul")` AND NOT `g_matmul()`, and that is measured rather than stylistic.
  `Tensor.empty` mints a FRESH `ParamArg.slot` from a process-global counter, so building
  the matmul twice in one process gives ALLOCs slots (0,1) and then (1,2) -- and the port
  emits slots (0,1) because it has one arena. MEASURED: emitting `binblob` after
  `matmul` in the same process reported `ONLY-BEND` ALLOCs on a `slot` field and nothing
  else, which is the harness disagreeing with itself about the fixture rather than the
  port disagreeing with tinygrad. `base` is the cache that makes the emission
  order-independent, and `cross` needs that: it compares two graphs in ONE process."""
  return UOp(Ops.BINARY, (base("matmul"),), b"tiny")


GRAPHS = {"matmul": g_matmul, "reduce": g_reduce, "buffer": g_buffer, "sink": g_sink,
          "range": g_range, "rangeflat": g_rangeflat, "cast": g_cast, "special": g_special,
          "binblob": g_binblob}

_BASE: dict[str, UOp] = {}


def base(graph: str) -> UOp:
  """BUILT ONCE. `Tensor.empty` mints a FRESH `ParamArg.slot` from a process-global
  counter every call -- MEASURED: two `Tensor.empty(4,3)` in one process give slots 0,1
  then 2,3 (`UOp.unique_num`, ops.py:842, "must never be reset"). So a clean emit and a
  planted emit that each built their own graph would differ in two SLOT FIELDS before the
  plant did anything, and the differ would be reporting the harness rather than the
  plant."""
  if graph not in _BASE:
    _BASE[graph] = GRAPHS[graph]()
  return _BASE[graph]


def _rebuild_with(ast: UOp, op: Ops, fn) -> UOp:
  """Rebuild the DAG replacing `fn(u)` for the node of `op` and `ast` itself. Written as a
  fold over the TOPOSORT (ops.py:297) rather than as a positional rebuild, because a
  positional rebuild of 18 nodes is 18 chances to name the wrong child."""
  par = {c: n for n in ast.toposort() for c in n.src}
  par[ast] = None
  new: dict[UOp, UOp] = {}

  def go(n: UOp) -> UOp:
    if n in new:
      return new[n]
    kids = [go(s) for s in n.src]
    # EVERY node is rebuilt from its (possibly replaced) children -- including the root,
    # which is what propagates a replacement upwards -- and the node of `op` is REPLACED
    # instead. Getting that backwards returns the input graph unchanged, which is what the
    # first version did: `pl is ast` and the plant reported AGREE.
    r = fn(n) if (par.get(n) is not None and n.op is op) else n.replace(src=tuple(kids))
    new[n] = r
    return r

  return go(ast)


def plant_dtype(ast: UOp) -> UOp:
  """Re-type the two ALLOCs to int32, so every node downstream of them changes dtype. MUL
  and ADD are commutative and `promo_dtype` handles an int mix, so the SHAPES of the
  downstream nodes change too -- which is the point: the differ must name `dtype` on each
  of them and not stop at "some node differs". Every op, arg, depth, tag, child count and
  child order is untouched, and CONSTs are NOT retyped (a CONST's dtype is the type of its
  arg, ops.py:199), so the CONST nodes must come out IDENTICAL."""
  def retype(n: UOp) -> UOp:
    if n.op is not Ops.ALLOC:
      return n
    a = n.arg
    return UOp(Ops.ALLOC, src=(), arg=ParamArg(a.slot, dtypes.int, a.size, device=a.device,
                                               bind_on_realize=True))
  return _rebuild_with(ast, Ops.ALLOC, retype)


def plant_srcswap(ast: UOp) -> UOp:
  """Swap the two children of the MUL. MUL is commutative in tinygrad, so this is a
  SEMANTIC no-op -- exactly why a differ that only counted nodes would miss it. Nothing
  else is touched, so the report must be the reordered pair ALONE and the pair's own
  fields must come out clean: `--plant srcswap` failing to flag the reordered pair's own
  fields is the half of this deliverable that a count-based differ cannot express."""
  def swap(n: UOp) -> UOp:
    return UOp(Ops.MUL, src=(n.src[1], n.src[0])) if n.op is Ops.MUL else n
  return _rebuild_with(ast, Ops.MUL, swap)


def plant_shape(ast: UOp) -> UOp:
  """Reverse the `(4, 3)` shape STACK's two CONST children, so the RESHAPE over it answers
  shape `(3, 4)` where it answered `(4, 3)`. Upstream's own lesson applied to a fixture:
  ops.bend:2432-2440 records that swapping two shape args leaves op, nsrc and the src
  sequence identical, which is why a count is not a gate.

  MEASURED, and it is why this plant reaches rung 2 and not rung 1: it moves the STACK's
  `src` ORDER, and `src` IS in the core, so the STACK's core moves and so does every
  consumer's. The report is six rung-2 pairs, and exactly one of them -- RESHAPE#5 -- names
  the `shape` field. What this ESTABLISHES is that a shape field is named as a shape field:
  it is not folded into the identity and it is not summarised as a node difference.
  (A shape change with `src` INTACT would land on rung 1. A CONST dtype plant cannot get
  there either, and the reason is worth stating because the obvious reading of ops.py:199
  is wrong: MEASURED, `UOp.const(4, dtypes.i32)` does NOT collide with `UOp.const(4)` --
  they are different objects with different keys -- because `UOp.const` (ops.py:629-635)
  ends in `.cast(dtype)` and so builds a `CAST`, not a second `CONST`. A CONST's dtype is
  therefore genuinely DERIVED from its arg (`dtype_from_uop`, ops.py:184-190) and cannot be
  set independently at all. Reported as a measured theorem, not closed with a row that
  encodes it.)

  WHAT RUNG 1 IS FOR, then, stated precisely: `dtype` and `shape` are DERIVED on both sides
  -- `UOp.dtype` -> `dtype_from_uop` (ops.py:247), `UOp.shape` -> `_shape` (ops.py:454) --
  and both read only op/src/arg, i.e. only the core's constituents. So a rung-1 mismatch
  cannot mean "the graphs differ"; it means the two IMPLEMENTATIONS of `dtype_from_uop` and
  `_shape` disagree about the same node, which is a real class of port bug (the port
  computes both in one FOLD, fold.bend's `DtShape`, a different implementation that can and
  does fail -- that is why `fold.shape` can answer `R`). Rung 1 has not fired on any graph
  measured today."""
  # The `(4, 3)` STACK, named by its CONST VALUES and not by its position: this graph has
  # two two-CONST STACKs, `(4,3)` and `(3,5)`, and picking by position would plant the wrong
  # one the day the graph grows a dimension. Note it CANNOT be named by `n.shape` -- a
  # STACK's shape is its element COUNT (`_shape`, ops.py:331), so all four of this graph's
  # STACKs answer `(2,)` or `(3,)`. The outer RESHAPE's `marg` is still `(4,1,3)` and the
  # element count is unchanged, so no other node's shape moves.
  sts = [n for n in ast.toposort() if n.op is Ops.STACK and [s.arg for s in n.src] == [4, 3]]
  assert len(sts) == 1, f"expected exactly one (4,3) STACK, got {len(sts)}"
  st = sts[0]
  return _rebuild_with(ast, Ops.STACK,
                       lambda n: UOp(Ops.STACK, src=(n.src[1], n.src[0])) if n is st else n)


def plant_bytes(ast: UOp) -> UOp:
  """TWO `Ops.BINARY` nodes of the SAME LENGTH with DIFFERENT CONTENT, hung off the root.

  This is the `bytes` residual made into a REPORTED MISMATCH. Before it, a length-only
  comparison was invisible: two graphs differing only in blob content scored identical, and
  the reason was stronger than "the printer shows less" -- MEASURED, the port's
  `ABlob{4}` makes the two the SAME arena node (`Arena.next` 2 after two inserts), while
  upstream's `UOp(Ops.BINARY, (), b"aaaa")` and `..., b"bbbb")` are different objects with
  different keys (`tinygrad/uop/ops.py:201` keys on `arg`). So this plant is expected to
  report the two nodes as ONLY-PY, because the port cannot express the second one at all.
  That is the point: an invisible hole has become a row."""
  b1 = UOp(Ops.BINARY, (), b"aaaa")
  b2 = UOp(Ops.BINARY, (), b"bbbb")
  return UOp(Ops.SOURCE, src=(ast, b1, b2), arg=None)


def plant_pyuop(ast: UOp) -> UOp:
  """A `PYLITERAL` whose arg holds a `UOp`, hung off the root. This is the nested-UOp
  residual made into a REPORTED MISMATCH. `at_value(u, "u")` counts the refusal and
  `SHAPE_NONE_HITS`-style the row shows the node as ONLY-PY, because the port has no
  `Arg` variant for a UOp and its `ATuple` cannot be told apart from PERMUTE's literal
  ints. MEASURED that the nested UOp is in neither `src` nor `toposort`, so the differ
  could not have resolved it even if the port could hold it."""
  return UOp(Ops.PYLITERAL, src=(ast,), arg=(UOp.const(4),))


def plant_opt(ast: UOp) -> UOp:
  """A `SINK` carrying a NON-DEFAULT `KernelInfo`: two `applied_opts` and a non-empty
  `opts_to_apply`. This is the `KernelInfo` residual made into a REPORTED MISMATCH, and it
  is also the regression row for the emitter CRASH: before the `enum.Enum` arm,
  `carg(Ops.SINK, ...)` raised `TypeError: vars() argument must have __dict__ attribute`
  on this exact value, so this plant is the smallest thing in the file that reproduces it.
  MEASURED: `OptOps` is a plain `Enum` and an enum MEMBER has no `__dict__`, so `vars()`
  is right to refuse."""
  from tinygrad.codegen.opt import Opt, OptOps
  from tinygrad.uop.ops import KernelInfo
  ki = KernelInfo(name="plant", applied_opts=(Opt(OptOps.TC, 0, 4), Opt(OptOps.SWAP)),
                  opts_to_apply=(Opt(OptOps.PADTO, 1),), beam=2)
  return UOp(Ops.SINK, src=(ast,), arg=ki)


PLANTS = {"dtype": plant_dtype, "srcswap": plant_srcswap, "shape": plant_shape,
          "bytes": plant_bytes, "pyuop": plant_pyuop, "opt": plant_opt}


def emit_py(graph: str, plant: str | None) -> list[str]:
  """The CPython side. A plant edits THIS SIDE'S COPY and nothing else -- never the live
  tree, never a port file. 400 oracles under `.agents/slop/` mutate a COPY for the same
  reason."""
  ast = base(graph)
  if plant:
    ast = PLANTS[plant](ast)
  # The arena indices are the TOPOSORT POSITIONS, so R1 is a construction-order number
  # rather than a hash. Deliberate: the differ pairs structurally, so `id` is for the
  # reader only, and a construction-order number is the only one checkable against
  # `print_uops`' own output.
  # R1's ALIGNMENT. CPython's ucache has no index; the port's arena spends index 0 on its
  # bottom node (ops.bend:1162-1168: "the arena starts with the bottom at index 0"), so this
  # side counts from 1 too. The ids are REPORTING ONLY and the differ never keys on them,
  # but with the alignment the two canonical files are byte-comparable and a plain
  # `diff 01-canon-py.txt 02-canon-bend-bound.txt` is ITSELF a check -- the cheapest one
  # in this file, and the one that fails first when an atom letter moves.
  lst = list(ast.toposort())
  ix = {id(n): i + 1 for i, n in enumerate(lst)}
  return [row_of(n, i + 1, ix) for i, n in enumerate(lst)]


# ---------------------------------------------------------------------------
# THE BEND SIDE. Re-run on an empty stream: `bend` stack-overflows on roughly 1 run in 20
# and prints nothing, which is indistinguishable from "this file has no rows" -- the trap
# that had twelve committed files print 0 rows for an hour.
def clean_env(dev: str) -> dict:
  """`PYTHONPATH` REMOVED (it contaminates a control) and `LC_ALL=C` SET (a locale-colated
  sort fabricates diffs, including on a no-op control)."""
  e = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
  e.update(LC_ALL="C", DEV=dev)
  return e


def emit_bend(dev: str, graph: str, tries: int = 5,
              probe: pathlib.Path | None = None) -> tuple[list[str], list[str]]:
  """`graph` is REQUIRED, with no default, and that is the fix rather than the style.
  MEASURED: `graph` defaulted to `"matmul"` and all three call sites passed only `dev`, so
  `--graph reduce` compared the py side's `sum(axis=1)` against the bend side's MATMUL --
  7 py rows against 18 bend rows, every one of them reported as a real difference, and the
  verdict said DISAGREE while naming no cause. A default that is also the DEFAULT `--graph`
  is a silent wrong answer: it is correct for the default invocation, so no test of the
  default invocation can see it, and the disagreement it produces looks like a port bug.
  Making the argument required turns a future omission into a TypeError.

  `probe` exists so the re-run guard can be SEEN TO FIRE: point it at a file that prints
  nothing and this must raise, not answer. Measured 20 consecutive runs of the real probe:
  20 x 18 rows, zero empty, so the trap never fired naturally today and an untested guard
  is exactly the guard that does not work."""
  """`probe` exists so the re-run guard can be SEEN TO FIRE: point it at a file that prints
  nothing and this must raise, not answer. Measured 20 consecutive runs of the real probe:
  20 x 18 rows, zero empty, so the trap never fired naturally today and an untested guard
  is exactly the guard that does not work."""
  notes = []
  for attempt in range(1, tries + 1):
    c = subprocess.run([str(BEND), str(probe or BEND_PROBE), graph], cwd=REPO, capture_output=True, text=True,
                       env=clean_env(dev), timeout=1800)
    lines = [ln for ln in c.stdout.splitlines() if ln.strip()]
    rows = [ln for ln in lines if not ln.startswith("#")]
    hdr = [ln for ln in lines if ln.startswith("#")]
    if rows:
      notes.append(f"bend attempt {attempt}: {len(rows)} rows, {' | '.join(hdr)}")
      return rows, notes
    notes.append(f"bend attempt {attempt}: 0 rows, rc={c.returncode}, "
                f"stderr tail: {' '.join(c.stderr.split())[-160:] or '(empty)'}")
  raise SystemExit("emit bend: 0 rows after %d attempts -- a FAILURE, not a verdict:\n  %s"
                   % (tries, "\n  ".join(notes)))


# ---------------------------------------------------------------------------
class Node:
  """One record. `cores[c]` is the child's CORE, filled by `build`."""

  def __init__(self, nid: str, f: list[str]):
    self.nid = nid
    self.op, self.dtype, self.shape, self.depth, self.tag, self.arg, self.src = f[1:]
    self.cores: dict[str, str] = {}
    # The child's COMMUTATIVE-CANONICAL core. A parent's `src` comparison under `equiv`
    # must use these and not `cores`, because a non-commutative parent of a commutative
    # child (the matmul's two PERMUTEs and its REDUCE) would otherwise still see the
    # child's ORDERED key and the reorder would propagate up the graph -- MEASURED, before
    # this existed `--equiv` left 2 rung-2 pairs disagreeing on `src` for PERMUTE#17 and
    # REDUCE#18 after it had already paired the MUL correctly.
    self.ecores: dict[str, str] = {}
    self.kidop: dict[str, str] = {}
    self.side = ""
    self.core = ""

  def __repr__(self) -> str:
    return f"<{self.op}#{self.nid}>"

  def key(self, equiv: bool) -> str:
    """`equiv=False` is `core` -- order-sensitive. `equiv=True` is the
    COMMUTATIVE-CANONICAL key: a commutative op's children contribute their cores SORTED,
    so `MUL(a, b)` and `MUL(b, a)` are ONE node and nothing else changes.

    This is the second of the two answers one fixture has to be able to give, and it is
    what makes "reordered but equivalent" something the differ EXPRESSES rather than
    guesses. Both answers are printed by `report`, because a differ that could only give
    one would be conflating "identical" with "equivalent" -- and those are different
    claims: `MUL(a,b)` and `MUL(b,a)` have the same `repr(arg)` (it is `repr(None)`), so a
    differ keying on `repr` calls them equal, which is the RIGHT answer for equivalence and
    the WRONG one for identity. MEASURED on `--plant srcswap`: `diff` reports the `src`
    field on `MUL py#16 vs bend#16`, `diff --equiv` reports AGREE.

    THE CANONICAL FORM MUST BE CANONICAL ALL THE WAY DOWN, and that was the second
    measured defect in `--equiv`. The first version sorted only the node's OWN children
    out of their ORDERED cores, so the MUL paired and then PERMUTE#17 -- a
    NON-commutative parent of the commutative MUL -- still carried the MUL's ordered key
    into its own key and still disagreed, and REDUCE#18 with it. Canonicalising only the
    node you are looking at propagates the difference upward, which is why the child's
    `ecore` is read here and not its `core`.
    """
    if not equiv:
      return self.core
    ks = [self.ecores[c] for c in self.src]
    if self.op in COMM:
      ks = sorted(ks)
    return hashlib.sha256((f"{self.op}\x00{self.depth}\x00{self.tag}\x00{self.arg}\x00"
                           + "|".join(ks)).encode()).hexdigest()

  @property
  def loose(self) -> str:
    """Rung 2. The arg with every dtype SPEL erased, plus the children's OPS rather than
    their cores -- so a node whose only difference is a dtype finds a partner and the
    difference is reported as the `dtype` field."""
    # SORTED, not in order: a reorder of two commutative children is a difference in the
    # `src` FIELD, and if the rung-2 key were order-sensitive the swapped node would fail
    # to pair at all and be reported as "only on one side" -- which is the one report a
    # differ must never give for a node that is present on both sides. Measured: with the
    # child ops in order, `--plant srcswap` printed `ONLY-PY=1 / ONLY-BEND=1` for the MUL
    # and never named its `src`.
    return (f"{self.op}\x00{self.tag}\x00{erase_depth(erase(self.arg))}\x00"
            + ",".join(sorted(self.kidop[c] for c in self.src)))

  def full(self, side: str) -> str:
    return (f"  {side}#{self.nid} {self.op} dtype={self.dtype} shape={self.shape} "
            f"depth={self.depth} tag={self.tag} arg={self.arg} src={self.src}")


def value_starts(arg: str, letter: str) -> list[tuple[int, int]]:
  """Every occurrence of `letter` that is a VALUE TAG rather than part of a string.

  The atom letters are single characters and a string payload is emitted RAW (`sNULL`,
  `s<name>`, and an Opt name like `OPT_SZ`), so a naive `arg.find("D")` finds the `D` in
  `sDefault` and rewrites it. The grammar's own rule is the fix: an atom letter is a value
  tag only when it sits where a VALUE starts -- at offset 0, or right after `(`, `,` or
  `:`. MEASURED: without this guard `erase` rewrote nothing at all in `P(i0,Di32,i12,...)`,
  because the first `)` after `D` was `P`'s own and the guard saw a comma, so
  `--plant dtype` reported its two ALLOCs as "only on one side" instead of pairing them and
  naming `dtype`.
  """
  out, i = [], 0
  while i < len(arg):
    if arg[i] == letter and (i == 0 or arg[i - 1] in "(,:"):
      j = i + 1
      while j < len(arg) and (arg[j].isalnum() or arg[j] == "_"):
        j += 1
      if j > i + 1:
        out.append((i, j))
        i = j
        continue
    i += 1
  return out


def erase(arg: str) -> str:
  """`D<name>` -> `D*`. Exhaustive by construction: a dtype appears in the normal form
  ONLY as `D<name>`, so one pass cannot miss a spelling, and `value_starts` is what keeps
  it off a string payload."""
  out, i, hits = [], 0, value_starts(arg, ATOMS["dtype"])
  for a, b in hits:
    out.append(arg[i:a])
    out.append(ATOMS["dtype"] + "*")
    i = b
  out.append(arg[i:])
  return "".join(out)


def erase_depth(arg: str) -> str:
  """`rg(i3,XWEAK,n(i0,i1))` -> `rg(i*,XWEAK,n(i0,i1))` -- the RANGE arg's DEPTH SLOT and
  nothing else.

  It exists because RUNG 2 COULD NOT NAME A DEPTH DIFFERENCE, which is MEASURED and is the
  third thing a differ has to get right. `loose` below erased the dtype and nothing else,
  and the two RANGE graphs differ in the depth AND in the axis-id list, so their `loose`
  keys differed, so they fell to rung 3 and were printed as two separate "ONLY ON THE ...
  SIDE" blocks -- the reader had to diff two lists BY EYE to see that the one difference
  was `depth`, which is the exact failure the whole file exists to remove. Erasing the
  depth slot pairs them, and `mismatches` then names `depth` and `arg` separately.

  Only the depth slot, and not every `i<digits>`: the axis ids in `n(i0,i1)` are also
  `u32` atoms, and erasing them too would make any two RANGEs pair, which is a weaker
  claim than it looks."""
  if not arg.startswith("rg(i"):
    return arg
  return "rg(i*" + arg[arg.index(","):]


def split_top(s: str) -> list[str]:
  """Split on the commas at DEPTH 0. `P(i0,Df32,i12,r(l0:0,l0:10),...)` has commas inside
  `r(..)`/`n(..)` and a naive `split(",")` would put field 8 in the wrong place -- which is
  exactly the failure a declared binding would have hidden."""
  out, cur, depth, i = [], [], 0, 0
  while i < len(s):
    c = s[i]
    if c in "([":
      depth += 1
    elif c in ")]":
      depth -= 1
    if c == "," and depth == 0:
      out.append("".join(cur))
      cur = []
    else:
      cur.append(c)
    i += 1
  out.append("".join(cur))
  return out


def devnames(lines: list[str]) -> set[str]:
  """The device names the stream actually carries, read off `ParamArg`'s EIGHTH field
  (ops.py:33, the declaration order this file emits). Only `P(..)` args have one, so a
  `s`-atom elsewhere is never mistaken for a device. Used as a PRECONDITION, not as the
  comparison -- the differ compares the device as part of `arg` either way."""
  out = set()
  for ln in lines:
    arg = unchunks(ln)[6]
    if arg.startswith("P("):
      out.add(split_top(arg[2:-1])[7])
  return out


# ============================================================================
# THE LEDGER. Every construct the normal form emits that is NOT a full structural
# comparison, with the reason and the count on BOTH sides, PRINTED ON EVERY REPORT.
#
# WHY IT EXISTS. A residual that is INVISIBLE is worse than one that is red, because an
# absent disagreement reads as an agreement. Each entry below was a thing the differ
# could not see, and the report said nothing -- so a graph full of them scored the same
# as a clean one. A fixed list with a `0/0` count is a LEDGER rather than a variable
# list: a construct that is PRESENT and lossy is a printed fact, and a construct that is
# ABSENT is a printed `0`, which is the one thing here that cannot be mistaken for
# "not started".
#
# Every entry was MEASURED; the measurement is named in the reason and the probe is under
# `runs/graphcmp/probe/`. Nothing in this table is an assertion about a docstring.
#
# The second element is the FIELD INDEX each marker can appear in, because a marker that
# lives in `shape` is not in `arg` and scanning the wrong one is a silent zero.
WIRE = ("id", "op", "dtype", "shape", "depth", "tag", "arg", "src")
LEDGER = (
  ("z", 6, "a realized BUFFER: device-object PRESENCE only",
   "Buffer has no `slot` (measured) and the port's is a P6 allocator slot; size/dtype/"
   "device/offset are already ParamArg fields 2/3/8 and ARE compared"),
  ("y", 6, "a bytes arg: CONTENT compared; the residual is the bytes CONST",
   "MEASURED 2026-10-04: `ABlob{bs}` (ops.bend:1062) holds the BYTES and `eq_arg.ABlob` "
   "(:1801) compares them, so the column is the full byte list; this row used to say "
   "LENGTH only. NOT comparable: a bytes CONST -- upstream's `PyConst` includes `bytes` "
   "(ops.py:122), the port's `Const` is CBool|CInt|CFloat|CInvalid (ops.bend:810-811), "
   "and graphcmp.bend's `konst` has no bytes arm at all"),
  ("u", 6, "a UOp nested in an arg: identity NOT compared",
   "measured: PYLITERAL's nested UOp is in neither `src` nor `toposort`, so it has no "
   "arena index here; the port's ATuple also spells PERMUTE's literal ints"),
  ("q", 6, "an applied option the port cannot resolve: COUNT only",
   "ops.bend:978 types applied_opts/opts_to_apply as List<U32>; upstream's elements are "
   "`Opt` dataclasses and no port file writes a non-empty list"),
  ("X!", 6, "an AxisType member with no counterpart at this tree",
   "measured at 3138973dc: `list(AxisType)` is DEVICE..PLACEHOLDER (8). The port keeps "
   "AXIS_REDUCE and AXIS_UNROLL, DELETED upstream by 78d482262, for six committed files"),
  ("BAD", 6, "the port's arena bottom: not a node",
   "ops.bend:1154 -- a read of an index that was never interned"),
  ("?", 3, "the port's fold produced no shape at all for this node",
   "PORT-ONLY, no upstream counterpart: `UOp.shape` always raises or returns a tuple "
   "(ops.py:455), so upstream has no third state. `?` cannot be produced by the py side"),
  ("E", 6, "an enum member outside {Ops, AxisType, AddrSpace}: NAME only",
   "`OptOps` (codegen/opt/__init__.py:6). Before the enum arm this CRASHED: the generic "
   "`vars()` fallback followed `__objclass__` into the enum CLASS, walked its 17 "
   "attributes, and died on a descriptor -- so a SINK with a non-empty applied_opts could "
   "not be emitted at all"),
)


def at_value(arg: str, marker: str) -> int:
  """How many times `marker` sits where a VALUE starts -- offset 0, or right after one of
  `( , : =`. `value_starts` below is the same scan with the extra rule that a NAME follows
  the letter; these atoms are a letter (or a two-character marker) and nothing else, so
  that rule would count zero. It is what keeps a marker inside a string payload
  (`sNULL`, `s<name>`) from being counted.

  `=` IS a value-start delimiter, and leaving it out was MEASURED to cost a count: the
  dataclass arm renders `name=value`, so `Opt(op=EOptOps.TC, ...)` puts every enum atom
  after an `=` and `--plant opt` reported `RESIDUALS IN THIS RUN: none` while the row it
  printed plainly contained `EOptOps.TC`. A ledger that misses its own row is worse than no
  ledger, which is the whole reason it exists."""
  n, i = 0, 0
  while True:
    i = arg.find(marker, i)
    if i < 0:
      return n
    if i == 0 or arg[i - 1] in "(,:=":
      n += 1
      i += len(marker)
    else:
      i += 1


def ledger(lines: list[str]) -> dict[str, int]:
  """`{marker: occurrences}` over the field each marker can appear in. The other seven
  fields are plain op/dtype/shape/depth/tag/src texts with nothing this file renders
  lossily in them, and scanning them would be scanning for nothing."""
  out = {m: 0 for m, _, _, _ in LEDGER}
  for ln in lines:
    f = unchunks(ln)
    for m, fi, _, _ in LEDGER:
      out[m] += at_value(f[fi], m)
  return out


def ledger_lines(py: dict[str, int], bd: dict[str, int]) -> list[str]:
  out = ["# LEDGER -- constructs this normal form does NOT compare in full. A `0/0` is a "
         "fact, not an absence:"]
  for m, fi, what, why in LEDGER:
    out.append(f"#   {m:<3} {WIRE[fi]:<5} py={py[m]:<4} bend={bd[m]:<4} {what}")
    out.append(f"#       {why}")
  # THE ONE FIELD WITH NO MARKER, because neither side can write one.
  # `KernelInfo.estimates: Estimates|None` (ops.py:1346) exists upstream, ops.bend DROPPED
  # it (P5, `tinygrad.renderer`), and `uop/render.bend:653` pins the literal
  # `estimates=None` in its place with the reason "it is None for every kernel this port
  # can build". So it is not a countable construct -- a count would be 0 by construction,
  # which is a claim -- it is a field neither side carries, and it is named here so that
  # "not compared" is a printed sentence rather than a silence.
  out.append("#   -   arg   py=n/a  bend=n/a  KernelInfo.estimates: NEITHER SIDE CARRIES IT "
             "(port dropped it, P5); upstream's value is None for every kernel the port can "
             "build, so the count would be 0 BY CONSTRUCTION and is not printed as one")
  return out


def residual_lines(py: dict[str, int], bd: dict[str, int]) -> list[str]:
  """The subset that is PRESENT on either side, so a reader does not have to scan the
  ledger's `0`s to find the live losses. Anything non-zero here is a known blind spot
  this run's agreement does NOT cover."""
  live = [(m, what) for m, _, what, _ in LEDGER if py[m] or bd[m]]
  if not live:
    return ["# RESIDUALS IN THIS RUN: none -- every ledger entry is 0 on both sides."]
  return ["# RESIDUALS IN THIS RUN: " + ", ".join(f"{m}={py[m]}/{bd[m]} ({what})"
                                                   for m, what in live) +
          " -- agreement below does NOT cover these."]


def build(lines: list[str], side: str) -> tuple[dict[str, Node], dict[str, Node],
                                                dict[str, Node]]:
  """(nodes by id, nodes by core, nodes by commutative-canonical core). The core is
  computed from the CHILDREN's cores, so the walk is a topological one; `order` is derived
  here rather than trusted from the emitter, and a cycle is a loud failure instead of a
  recursion."""
  recs = {}
  for ln in lines:
    f = unchunks(ln)
    if len(f) != 8:
      raise SystemExit(f"{side}: expected 8 chunks, got {len(f)}: {ln[:90]!r}")
    recs[f[0][1:]] = f
  kids = {nid: [x[1:] for x in f[7][2:-1].split(",") if x] for nid, f in recs.items()}
  for nid, cs in kids.items():
    for c in cs:
      if c not in recs:
        raise SystemExit(f"{side}: node {nid} names an unknown child {c}")
  node, bycore, byequiv, done, order, path = {}, {}, {}, set(), [], set()

  def go(nid):
    if nid in done:
      return
    if nid in path:
      raise SystemExit(f"{side}: CYCLE at node {nid}")
    path.add(nid)
    for c in kids[nid]:
      go(c)
    path.discard(nid)
    done.add(nid)
    order.append(nid)
    f = recs[nid]
    n = Node(nid, f)
    n.side = side
    n.src = kids[nid]           # CHILD INDICES, not the printed tuple -- R8 is a list
    node[nid] = n
    for c in kids[nid]:
      n.cores[c] = node[c].core
      n.ecores[c] = node[c].key(True)
      n.kidop[c] = node[c].op
    n.core = hashlib.sha256((f"{n.op}\x00{n.depth}\x00{n.tag}\x00{n.arg}\x00"
                             + "|".join(n.cores[c] for c in kids[nid])).encode()).hexdigest()
    bycore.setdefault(n.core, []).append(n)
    byequiv.setdefault(n.key(True), []).append(n)

  for nid in recs:
    go(nid)
  return node, bycore, byequiv


FIELDS = ("dtype", "shape", "depth", "tag", "arg", "src")


def mismatches(a: Node, b: Node, equiv: bool = False) -> list[str]:
  """NAMES the fields that differ, never a count. `src` is compared as the ordered list of
  the two sides' CORE keys, so a swap reads as an `src` difference on the PARENT and as
  nothing at all on the children -- the property `--plant srcswap` exists to show. Under
  `equiv` a commutative parent's `src` is compared SORTED, which is the whole difference
  between "identical" and "equivalent" and is why both modes are runnable."""
  out = []
  for f in FIELDS:
    if f == "src":
      # `equiv` compares the children's CANONICAL keys, sorted for a commutative parent.
      # Both halves are needed: canonical-without-sorting still makes a commutative
      # parent disagree, and sorted-without-canonical still lets a NON-commutative parent
      # of a commutative child disagree.
      cm = (lambda n: [n.ecores[c] for c in n.src]) if equiv else (lambda n: [n.cores[c] for c in n.src])
      ka, kb = cm(a), cm(b)
      if equiv and a.op in COMM:
        ka, kb = sorted(ka), sorted(kb)
      if ka != kb:
        out.append(f"src  py={[x[:8] for x in ka]} bend={[x[:8] for x in kb]}")
    elif getattr(a, f) != getattr(b, f):
      out.append(f"{f:<5} py={getattr(a, f)} bend={getattr(b, f)}")
  return out


def report(py: list[str], bd: list[str], plant: str | None,
           lname: str = "py", rname: str = "bend", equiv: bool = False) -> tuple[int, str]:
  """`lname`/`rname` label the two sides in every line they appear in. They are PARAMETERS,
  not the literals "py"/"bend", because MEASURED: hardcoding them made `cross` and `control`
  -- which deliberately compare a side against ITSELF and one graph against another -- print
  "ONLY ON THE PYTHON SIDE" for nodes that are only on the BEND side. A wrong label in a
  report is not cosmetic here: `cross` is the check that decides whether the differ can see
  a difference at all, and a reader who is told the wrong side sent a node stops trusting
  the rest of the block. Defaulted to the two real sides so every existing call is unchanged.

  `equiv=True` pairs on the COMMUTATIVE-CANONICAL core and compares a commutative parent's
  `src` sorted. See `Node.key`. It is a mode and not a second differ, so there is one
  implementation of "compare two graphs" and the mode is the only thing that varies.
  """
  pnodes_all, pcore, pequiv = build(py, lname)
  bnodes_all, bcore, bequiv = build(bd, rname)
  pcore, bcore = (pequiv, bequiv) if equiv else (pcore, bcore)
  pnodes = {n.nid: n for ns in pcore.values() for n in ns}
  bnodes = {n.nid: n for ns in bcore.values() for n in ns}

  shared = sorted(set(pcore) & set(bcore))
  only_p = [n for k in sorted(set(pcore) - set(bcore)) for n in pcore[k]]
  only_b = [n for k in sorted(set(bcore) - set(pcore)) for n in bcore[k]]

  hard, soft = [], []
  for k in shared:
    for a, b in zip(pcore[k], bcore[k]):
      for d in mismatches(a, b, equiv):
        hard.append(f"MISMATCH {a.op:<9} {lname}#{a.nid} vs {rname}#{b.nid}  {d}")
  # MEASURED, and it is a limit worth naming: `zip` PAIRS IN ORDER and TRUNCATES, so two
  # sides with the same set of cores and a different MULTIPLICITY would lose the extra
  # copies silently. No graph built here reaches it -- a core is a hash of the node's whole
  # subtree, and two identical subtrees are the same arena node on the port by
  # construction -- but it is a place where "no disagreement" would be a truncation rather
  # than an agreement, so it is counted and printed rather than left to be discovered.
  trunc = sum(min(len(pcore[k]), len(bcore[k])) for k in shared) - len(shared)

  # RUNG 2, ONE-TO-ONE. Pairing every leftover with every other leftover that shares a
  # `loose` key produces a cartesian product: all five RESHAPEs of this graph share one
  # `loose` key (arg `N`, src ops `RESHAPE,RESHAPE`) and were paired with each other, which
  # is a report full of crosswise nonsense. So each leftover takes its BEST candidate --
  # most agreeing fields -- and a candidate that is not a UNIQUE argmax is not taken at
  # all, and both nodes fall through to rung 3 and are printed in full.
  taken_b = set()
  pairs = []
  for a in only_p:
    cands = [b for b in only_b if b.loose == a.loose and id(b) not in taken_b]
    if not cands:
      continue
    scored = sorted(((len(mismatches(a, b, equiv)), b) for b in cands),
                    key=lambda p: (p[0], p[1].nid))
    if len(scored) > 1 and scored[0][0] == scored[1][0]:
      continue                              # ambiguous: no mutual best, so no claim
    pairs.append((a, scored[0][1]))
    taken_b.add(id(scored[0][1]))
  for a, b in pairs:
    soft.append(f"MISMATCH {a.op:<9} py#{a.nid} vs {b.side}#{b.nid}  (no shared core; paired "
                f"one-to-one on the dtype- and depth-erased arg)")
    soft += ["    " + d for d in mismatches(a, b, equiv)]
  only_p = [n for n in only_p if not any(n is a for a, _ in pairs)]
  only_b = [n for n in only_b if id(n) not in taken_b]

  # RUNG 3.5 -- SAME OP, UNPAIRED, DIFFED FIELD BY FIELD. It exists because of a MEASURED
  # failure of this file's own report: the two RANGE graphs (`--graph range` and
  # `--graph rangeflat`) differ in `depth` AND in the axis-id list, so rung 2 cannot pair
  # them -- correctly, their `arg`s really are different -- and rung 3 printed them as two
  # separate "ONLY ON THE ... SIDE" blocks. A reader then had to diff two lists BY EYE to
  # learn that the one difference was `depth`, which is precisely the reading this file
  # exists to replace. So the leftovers are cross-referenced where the pairing is
  # UNAMBIGUOUS (one node of that op on each side) and the fields are named. Nothing is
  # summarised away: both nodes are still printed in full by rung 3 below.
  cross = []
  for a in list(only_p):
    cands = [b for b in only_b if b.op == a.op]
    if len(cands) != 1:
      continue
    b = cands[0]
    ds = mismatches(a, b, equiv)
    if ds:
      cross.append(f"#   {a.op} {lname}#{a.nid} vs {rname}#{b.nid}  (same op, unpaired)")
      cross += ["#     " + d for d in ds]

  o = [f"# {lname} rows={len(pnodes_all)}  {rname} rows={len(bnodes_all)}  "
       f"plant={plant or 'none'}  mode={'EQUIV' if equiv else 'ORDERED'}",
       f"# devices {lname}={sorted(devnames(py))} {rname}={sorted(devnames(bd))}  "
       f"(both sides emit the NAME: CPython's is `Compiled.device`, the port's is "
       f"`uop/render.bend:363` on the tag)"]
  o += residual_lines(ledger(py), ledger(bd))
  o += [f"# SHARED cores={len(shared)}  ONLY-{lname.upper()}={len(only_p)}  "
        f"ONLY-{rname.upper()}={len(only_b)}  "
        f"field-mismatches={len(hard)}  rung2-pairs={sum(1 for x in soft if x.startswith('MIS'))}"
        f"  rung3.5-crossrefs={len(cross) // 2}  zip-truncated={trunc}"]
  o += hard
  if soft:
    o.append("# RUNG 2 -- paired on the dtype- and depth-erased arg, so these ARE the same node:")
    o += soft
  if cross:
    o.append(f"# RUNG 3.5 -- {len(cross) // 2} node(s) present on both sides, same op, "
             f"NOT pairable on the arg, and their differing FIELDS are named here so the "
             f"two rung-3 blocks below do not have to be read against each other by eye:")
    o += cross
  if only_p:
    o.append(f"# ONLY ON THE {lname.upper()} SIDE ({len(only_p)}), IN FULL:")
    o += [n.full(lname) for n in sorted(only_p, key=lambda n: int(n.nid))]
  if only_b:
    o.append(f"# ONLY ON THE {rname.upper()} SIDE ({len(only_b)}), IN FULL:")
    o += [n.full(rname) for n in sorted(only_b, key=lambda n: int(n.nid))]
  o += ledger_lines(ledger(py), ledger(bd))
  # The dead shape arm, MEASURED on this run rather than asserted in a comment. `shape`
  # never returns None upstream (ops.py:455 raises instead), so this must read 0; a
  # non-zero here means the normal form's `N` is live and the two sides disagree about
  # what it means, which is the collision `--graph sink` found.
  o.append(f"# shape-N hits py={SHAPE_NONE_HITS} (expected 0: `UOp.shape` RAISES instead "
           f"of returning None, ops.py:455 -- probed over all 12 no-shape ops)")
  same = not hard and not soft and not only_p and not only_b
  # THE VERDICT CARRIES ITS DENOMINATOR, and that is a rule rather than a nicety.
  # `AGREE` on 2 nodes and `AGREE` on 19 are different claims and printing them the same
  # way is how a thin comparison gets read as a broad one -- six findings today were
  # "compared nothing" reporting as agreement. So the one line states NODES, FIELDS and
  # GRAPHS, and a comparison whose denominator is small says so in the same line the
  # reader is already looking at.
  o.append(f"# DENOMINATOR: graphs=2 (1 {lname} + 1 {rname})  "
           f"nodes={len(pnodes_all)}/{len(bnodes_all)}  "
           f"fields={len(FIELDS)}  field-records={len(pnodes_all) * len(FIELDS)}  "
           f"shared-cores={len(shared)}  commutative-ops={len(COMM)}")
  o.append(f"# VERDICT: {'AGREE' if same else 'DISAGREE'}")
  return (0 if same else 1), "\n".join(o)


# ---------------------------------------------------------------------------
def selfcheck() -> int:
  """The atom table and the chunk reader, ASSERTED rather than assumed."""
  bad = []
  if len(set(ATOMS.values())) != len(ATOMS):
    bad.append(f"atom letters collide: {ATOMS}")
  for s in ["", "a", "a b", "PTX tensor_cores sm_75", "x:y", "n(i1,i2)", "name = [value]"]:
    try:
      got = unchunks(chunk(s))
    except ValueError as e:
      got = f"raised {e}"
    if got != [s]:
      bad.append(f"chunk round-trip failed for {s!r}: {got!r}")
  if chunk("PTX tensor_cores sm_75").split(":", 1)[0] != "22":
    bad.append("the count is not a byte count")
  # A CHUNK THAT CONTAINS A SPACE, which the reader used to refuse. MEASURED: the first
  # DEBUG row is `arg=smem|memory reduced from 0.01 MB -> 0.01 MB, 5 -> 2 bufs` and the
  # old reader raised `chunks not space-separated`, so the DEBUG lane reported "0 trace
  # rows" -- a reader that returned fewer rows than the emitter wrote, as a COUNT.
  if unchunks(chunk("memory reduced from 0.01 MB")) != ["memory reduced from 0.01 MB"]:
    bad.append("a chunk containing spaces does not survive the reader")
  if unchunks(chunk("a b") + " " + chunk("c")) != ["a b", "c"]:
    bad.append("two chunks, the first containing spaces, do not round-trip")
  if unchunks(chunk("a") + " " + chunk("PTX tensor_cores sm_75")) != ["a", "PTX tensor_cores sm_75"]:
    bad.append("a row name with spaces does not survive as the second chunk")
  for s in ["é", "\u00ff"]:
    try:
      chunk(s)
      bad.append(f"non-ASCII accepted: {s!r}")
    except ValueError:
      pass
  # THE LEDGER MARKERS MUST BE FINDABLE AND MUST NOT COLLIDE WITH THE OTHER SPELLINGS.
  # `unrealized` used to be the absent-buffer spelling; it CONTAINS `realized` as a
  # substring and STARTS WITH the ledger's `u`, so at a value position -- exactly where
  # it sat -- a scan counted the absent case as a present one AND counted a nested UOp
  # that was not there. Both were MEASURED by writing the scan that way first. The
  # absence is now `N`, uniform with the other six `Maybe` fields of the same record.
  for m, fi, _, _ in LEDGER:
    if m not in ATOMS.values() and m not in ("X!", "BAD", "?"):
      bad.append(f"ledger marker {m!r} is neither an atom letter nor a declared literal")
    if m in ATOMS["none"] and m != ATOMS["none"]:
      bad.append(f"ledger marker {m!r} collides with the absence atom")
    if not 0 <= fi < len(WIRE):
      bad.append(f"ledger marker {m!r} names field {fi}, outside the {len(WIRE)} fields")
  if at_value(f"N,{ATOMS['bytes']}4,{ATOMS['uop']},{ATOMS['opt']})", "y") != 1:
    bad.append("at_value does not count a bytes atom at a value position")
  if at_value(f"N,{ATOMS['bytes']}4,{ATOMS['uop']},{ATOMS['opt']})", "u") != 1:
    bad.append("at_value does not count exactly one nested-UOp atom")
  if at_value("sAXIS!no", "X!") != 0:
    bad.append("at_value counted a marker inside a string payload")
  if at_value("op=EOptOps.TC", "E") != 1:
    bad.append("at_value misses a dataclass value after '=' (--plant opt counted 0)")
  # `--equiv`'s whole answer depends on this set being non-empty and on `MUL` being in
  # it, because MUL is the op `plant_srcswap` reorders. An EMPTY set would make `--equiv`
  # the identity and print AGREE for the reordered pair -- which is the shape of the
  # failure this file is about, so it is asserted rather than assumed.
  if not COMM:
    bad.append("COMM is empty: `--equiv` would be the identity and AGREE for everything")
  if "MUL" not in COMM:
    bad.append(f"MUL is not in the commutative set {sorted(COMM)}: `--plant srcswap` "
               f"reorders a MUL, so `--equiv` could not answer for it")
  print("# SELFCHECK: " + ("OK" if not bad else "FAIL"))
  for b in bad:
    print("#   " + b)
  return 0 if not bad else 1


# ============================================================================
# THE COMMANDS. `diff` is the artifact: one command, no arguments beyond the graph name,
# one unambiguous verdict line. Everything else here exists to make that one line
# trustworthy -- `control` shows it is quiet against itself, `cross` and `conf` show it is
# loud against something else, `dbg` runs it across DEBUG levels on a FIXED graph, and
# `selfcheck` asserts the pieces it rests on.
def debug_run(dev: str, level: int, tries: int = 5) -> tuple[list[str], list[str]]:
  """ONE bend process at ONE `DEBUG` level, with the 0-row re-run guard `emit_bend` has.

  `DEBUG` GOES IN THE ENVIRONMENT and not in an argument, because that is where the port
  reads it: `H.debug()` is `IO(U32)` over `getenv_int("DEBUG", 0)` (helpers.bend:307-308).
  Threading it as a parameter instead would test a second mechanism -- there is a standing
  rule in this repo that `DEBUG` is a ContextVar and therefore a PARAMETER
  (`schedule/allreduce.bend`'s header, "THE FLAGS ARE PARAMETERS"), and the two readings
  are both legitimate, so the probe reads the ENV and the sites are still reached through
  the port's own `*_dbg*` defs with `d` threaded in. Which of the two is under test is
  stated rather than blurred: this exercises the ENV READ and the seven gates."""
  rows, notes = [], []
  for attempt in range(1, tries + 1):
    e = clean_env(dev)
    e["DEBUG"] = str(level)
    c = subprocess.run([str(BEND), str(BEND_DBG)], cwd=REPO, capture_output=True, text=True,
                       env=e, timeout=1800)
    lines = [ln for ln in c.stdout.splitlines() if ln.strip()]
    got = [ln for ln in lines if not ln.startswith("#")]
    if got:
      notes.append(f"DEBUG={level} attempt {attempt}: {len(got)} rows")
      return got, notes
    notes.append(f"DEBUG={level} attempt {attempt}: 0 rows, rc={c.returncode}, "
                 f"stderr tail: {' '.join(c.stderr.split())[-160:] or '(empty)'}")
  raise SystemExit("emit debug: 0 rows after %d attempts -- a FAILURE, not a verdict:\n  %s"
                   % (tries, "\n  ".join(notes)))


def split_debug(rows: list[str]) -> tuple[list[str], list[str]]:
  """(graph rows, trace rows). The `SITE` op is the discriminator, and it is a COLUMN
  rather than a prefix because a prefix would be a second wire format in one file."""
  graph, trace = [], []
  for ln in rows:
    try:
      f = unchunks(ln)
    except ValueError:
      continue                       # a blank separator line, not a row
    (trace if len(f) == 8 and f[1] == "SITE" else graph).append(ln)
  return graph, trace


def cmd_dbg(dev: str, levels: list[int], graph: str) -> int:
  """THE DEBUG-LEVEL COMPARISON, and the reason it is well-posed is the PRECONDITION.

  `DEBUG` CHANGES CONTROL FLOW, so comparing a graph emitted at level 0 against one
  emitted at level 2 would be comparing two different programs and calling the delta a
  defect. So the graph is built ONCE inside the probe (`GC.matmul_of`, imported from
  graphcmp.bend rather than copied) and every run prints that graph's own rows; this
  function DIGESTS them per level and REFUSES to compare if two digests differ. Exit 2 on
  a mismatch, which is a FAILURE and never a verdict -- the same rule as the 0-row guard.

  The graph is FIXED BY CONSTRUCTION as well as by check: the probe's `main` builds the
  graph once and hands the SAME `Found` to both the row printer and the trace walk, so
  there is no code path on which the level could reach the graph at all.
  """
  digs, traces, notes = {}, {}, []
  for L in levels:
    rows, nt = debug_run(dev, L)
    notes += nt
    graph, trace = split_debug(rows)
    if not graph or not trace:
      raise SystemExit(f"DEBUG={L}: {len(graph)} graph rows and {len(trace)} trace rows -- "
                       f"a FAILURE, not a verdict (both must be non-empty)")
    digs[L] = hashlib.sha256("\n".join(graph).encode()).hexdigest()
    traces[L] = trace
  uniq = sorted(set(digs.values()))
  for n in notes:
    print("# " + n)
  print(f"# DEBUG LEVELS COMPARED: {levels}  (the ONLY difference between the runs is DEBUG)")
  print(f"# GRAPH HELD FIXED: digest per level " +
        " ".join(f"{L}={d[:12]}" for L, d in digs.items()) +
        f"  distinct={len(uniq)}" + ("" if len(uniq) == 1 else
                                     "  -- NOT WELL-POSED, and this is NOT a verdict"))
  if len(uniq) != 1:
    print("# The graph moved with the level, so a difference below would be a difference "
          "between two different programs. Exit 2.", file=sys.stderr)
    return 2
  rc = 0
  for a, b in zip(levels, levels[1:]):
    print(f"# ---- DEBUG {a} vs DEBUG {b} ----")
    r, txt = report(traces[a], traces[b], None, f"DEBUG{a}", f"DEBUG{b}")
    print(txt)
    rc |= r
  print(f"# DEBUG VERDICT: {'the levels are DISTINGUISHABLE and the graph was fixed' if rc else 'NO LEVEL DISTINGUISHES ANYTHING -- see the residual ledger'}")
  return 0 if rc else 1


# ============================================================================
# THE THREE CONFLATIONS, as one command with one verdict line each. A differ that has
# only ever printed AGREE is unverified -- it may be comparing nothing, or comparing the
# same object to itself -- and these are the three cases that separate "it works" from
# "it agrees".
def field_named(txt: str, field: str) -> bool:
  """Is `field` reported AS A NAMED FIELD rather than merely appearing somewhere?

  The distinction is the whole point and the loose version got it wrong: `"depth" in txt`
  is satisfied by the rung-3 full dump, which prints `depth=i0` for EVERY node it dumps,
  so CONFLATION 2 passed for a report that had named nothing. MEASURED: the strict form
  below and the loose form disagree on exactly that case. The `#` must come off first --
  these are comment lines, so `.strip()` alone leaves the marker and every prefix test
  fails."""
  return any(ln.lstrip("#").strip().startswith(field + " ") for ln in txt.splitlines())


def cmd_conf(dev: str) -> int:
  """Each case states the CONFLATION, the EXPECTED answer and the ANSWER, and prints the
  denominator for it. None of the three is a row whose expectation is a copy of the
  implementation's own behaviour: two of them are measured off CPython (`repr(arg)`, the
  `depth` pair) and the third is checked against the op's own commutativity, read from
  `GroupOp.Commutative` rather than typed."""
  ok = True
  out = []

  # ---- CONFLATION 1: `repr(arg)` EQUAL, STRUCTURE DIFFERENT ---------------------
  # `--plant srcswap` on the REAL two-sided diff, because a difference planted on the
  # py side and seen by the bend side is the strongest form: the two ARENAS are separate
  # objects in separate processes and the disagreement names a node in each.
  m0 = base("matmul")
  swapped = PLANTS["srcswap"](m0)
  mul0 = [n for n in m0.toposort() if n.op is Ops.MUL][0]
  mul1 = [n for n in swapped.toposort() if n.op is Ops.MUL][0]
  out.append("# CONFLATION 1 -- `arg` differs STRUCTURALLY but `repr(arg)` is IDENTICAL.")
  out.append(f"#   MEASURED: repr(arg) before={mul0.arg!r} after={mul1.arg!r} "
             f"equal={mul0.arg.__repr__() == mul1.arg.__repr__()}  "
             f"and the normal form's arg text before={carg(Ops.MUL, mul0.arg)!r} "
             f"after={carg(Ops.MUL, mul1.arg)!r}")
  out.append("#   So a differ keying on `repr` would report NO difference here, and a "
             "differ keying on structure must report the `src` field.")
  rc, txt = report(emit_py("matmul", None), emit_py("matmul", "srcswap"), "srcswap",
                   "ordered", "srcswap")
  for ln in txt.splitlines():
    if ln.startswith(("MISMATCH", "    ", "# VERDICT", "# SHARED", "# DENOMINATOR",
                      "# RUNG", "#   ")):
      out.append(ln)
  named = field_named(txt, "src")
  out.append(f"# CONFLATION 1 VERDICT: {'OK -- names src on the reordered node' if rc and named else 'FAIL -- did not name src'} "
             f"(expected DISAGREE naming src; got rc={rc})")
  ok = ok and rc == 1 and named

  # ---- CONFLATION 2: SAME `arg`, DIFFERENT `depth` ------------------------------
  # Two RANGEs, one flat and one nested. The differ must name `depth`, and it must do so
  # on a graph where the two sides' OTHER fields agree, or the naming is not attributable.
  r_flat, r_nest = base("rangeflat"), base("range")
  out.append("# CONFLATION 2 -- the same op with a different `depth`, on a graph whose "
             "other fields agree.")
  out.append(f"#   MEASURED: rangeflat arg={r_flat.arg!r} depth={cdepth(r_flat)}   "
             f"range arg={r_nest.arg!r} depth={cdepth(r_nest)}")
  rc2, txt2 = report(emit_py("rangeflat", None), emit_py("range", None), "depth-pair",
                     "rangeflat", "range")
  for ln in txt2.splitlines():
    if ln.startswith(("MISMATCH", "    ", "# VERDICT", "# SHARED", "# DENOMINATOR",
                      "# RUNG", "#   ")):
      out.append(ln)
  dnamed = field_named(txt2, "depth")
  out.append(f"# CONFLATION 2 VERDICT: {'OK -- names depth' if rc2 and dnamed else 'FAIL -- did not name depth'} "
             f"(expected DISAGREE naming depth; got rc={rc2})")
  ok = ok and rc2 == 1 and dnamed
  # AND the negative control that makes the naming attributable: each RANGE agrees with
  # the PORT against itself, so `depth` is not a field that merely reads unequal.
  out.append("#   CONTROL (see cmd_diff for the run): `diff --graph range` and "
             "`diff --graph rangeflat` each report AGREE against the port, so the depth "
             "difference above is between two graphs and not a field the port always gets "
             "wrong. Recorded in runs/graphcmp/D/C2b-*.txt.")

  # ---- CONFLATION 3: REORDERED BUT EQUIVALENT -----------------------------------
  out.append("# CONFLATION 3 -- the SAME reordered pair under the commutative-canonical "
             "key. Expected: AGREE.")
  rc3, txt3 = report(emit_py("matmul", None), emit_py("matmul", "srcswap"), "srcswap",
                     "ordered", "srcswap", equiv=True)
  for ln in txt3.splitlines():
    if ln.startswith(("# VERDICT", "# SHARED", "# DENOMINATOR", "# ordered rows")):
      out.append(ln)
  out.append(f"#   commutative ops READ FROM CPython: {sorted(COMM)}")
  out.append(f"# CONFLATION 3 VERDICT: {'OK -- AGREE under --equiv' if rc3 == 0 else 'FAIL -- still disagrees'} "
             f"(expected rc=0; got rc={rc3})")
  ok = ok and rc3 == 0

  print("\n".join(out))
  print(f"# CONFLATION VERDICT: {'ALL THREE DISTINGUISHED' if ok else 'AT LEAST ONE CONFLATION IS NOT DISTINGUISHED'}")
  return 0 if ok else 1


def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("cmd", choices=["emit", "diff", "control", "cross", "selfcheck", "dbg",
                                  "conf"])
  ap.add_argument("--graph", choices=sorted(GRAPHS), default="matmul")
  ap.add_argument("--side", choices=["py", "bend"], default="py")
  ap.add_argument("--plant", choices=sorted(PLANTS), default=None)
  ap.add_argument("--dev", default="CPU",
                  help="CPU is the one device the port's arena tag 0 names; see the "
                       "argument's own comment in git history for why this is not "
                       "`os.environ.get('DEV')`")
  ap.add_argument("--equiv", action="store_true",
                  help="compare on the COMMUTATIVE-CANONICAL core: a commutative op's "
                       "children are matched as a multiset, so MUL(a,b) and MUL(b,a) "
                       "AGREE. Without it the pair DISAGREES on `src`")
  ap.add_argument("--levels", default="0,1,2",
                  help="DEBUG levels for `dbg`; the only difference between the runs")
  ap.add_argument("--bend-probe", default=None,
                  help="override the port-side probe; used to SEE the 0-row re-run guard fire")
  a = ap.parse_args()
  global COMM
  os.environ["DEV"] = a.dev
  load_tinygrad()
  COMM = commutative()

  if a.cmd == "selfcheck":
    return selfcheck()
  if a.cmd == "conf":
    return cmd_conf(a.dev)
  if a.cmd == "dbg":
    return cmd_dbg(a.dev, [int(x) for x in a.levels.split(",")], a.graph)
  if a.cmd == "emit":
    if a.side == "py":
      import tinygrad
      print(f"# graph={a.graph} plant={a.plant or 'none'} tree={tinygrad.__file__}", file=sys.stderr)
      print("\n".join(emit_py(a.graph, a.plant)))
    else:
      # `probe` REACHES THIS CALL. It did not, and that is the THIRD instance of the same
      # defect in this file's flags -- `--graph` defaulted, `--plant-side` was never read,
      # and `--bend-probe` was read once and handed only to `diff`/`control`/`cross`, so
      # `emit --side bend --bend-probe <a file that prints nothing>` ran the REAL probe and
      # answered with 18 rows. MEASURED: the guard is meant to be SEEN TO FIRE
      # (`emit_bend`'s `probe` argument exists for exactly that) and the one command whose
      # job is to emit could not show it. A guard that only one of three commands can
      # exercise is a guard that will rot.
      rows, notes = emit_bend(a.dev, a.graph, probe=pathlib.Path(a.bend_probe) if a.bend_probe else None)
      print("\n".join("# " + n for n in notes), file=sys.stderr)
      print("\n".join(rows))
    return 0
  # `--bend-probe` is read ONCE, here, and every bend emission goes through it. MEASURED
  # before this line existed: the flag was parsed and then used by `diff` alone, so
  # `control --bend-probe X` and `cross --bend-probe X` silently ran the REAL probe. That is
  # the same defect as the `--graph` one this file was measured to already have -- a flag
  # that is accepted and then does not reach the code it names -- and it is worse in a
  # probe harness, because the whole point of a mutant probe is to be load-bearing somewhere.
  probe = pathlib.Path(a.bend_probe) if a.bend_probe else None

  if a.cmd == "control":
    # A differ never seen to agree with ITSELF is not known to work.
    ok = True
    for name, get in (("py", lambda: emit_py(a.graph, a.plant)),
                      ("bend", lambda: emit_bend(a.dev, a.graph, probe=probe)[0])):
      rc, txt = report(get(), get(), a.plant, name, name, a.equiv)
      print(f"== CONTROL {name} vs itself: rc={rc}\n{txt}")
      ok = ok and rc == 0
    print(f"# CONTROL VERDICT: {'OK' if ok else 'THE DIFFER DISAGREES WITH ITSELF'}")
    return 0 if ok else 1
  if a.cmd == "cross":
    # THE OTHER HALF OF "the differ has been SEEN to disagree". `control` shows it is quiet
    # on a side against itself; this shows it is LOUD on two DIFFERENT graphs. A differ that
    # answers AGREE to `matmul` and to `sum(axis=1)` is worse than no differ, and the only
    # way to know it is not that one is to ask.
    #
    # BOTH SIDES, and that is the fix rather than a nicety. MEASURED: `cross` used to ask
    # only the py side, and the py side is the one that cannot have this bug -- it is handed
    # `graph` by `emit_py` and selects on it. The bend side is the one that can silently
    # IGNORE its graph argument, and it did: `emit_bend` defaulted `graph` to `"matmul"` and
    # every call site passed only `dev`, so asking the bend side to render `reduce` returned
    # matmul's 18 nodes and `diff --graph reduce` reported DISAGREE with no cause. A check
    # that only exercises the side which cannot fail is not a check. Now the bend side is
    # asked for BOTH graphs and compared, so a `graph` argument that stops reaching it is
    # LOUD here instead of silent in `diff`.
    other = [g for g in sorted(GRAPHS) if g != a.graph]
    ok = True
    for name, get in (("py", lambda g: emit_py(g, None)),
                      ("bend", lambda g: emit_bend(a.dev, g, probe=probe)[0])):
      rc, txt = report(get(a.graph), get(other[0]), f"{a.graph}-vs-{other[0]}",
                       f"{name} {a.graph}", f"{name} {other[0]}")
      print(txt)
      ok = ok and bool(rc)
    print(f"# CROSS VERDICT: {'OK -- it disagrees' if ok else 'IT AGREED WITH A DIFFERENT GRAPH'}")
    return 0 if ok else 1
  bd, notes = emit_bend(a.dev, a.graph, probe=probe)
  py = emit_py(a.graph, a.plant)
  # THE PRECONDITION. The port's fixture names one device and the py graph carries
  # whatever `--dev` opened, so the two device sets must be EQUAL before the cores mean
  # anything: an ALLOC whose device differs has a different `core`, which propagates to
  # every consumer and reports as a cascade of `src` differences with the cause in none of
  # them. Exit 2 -- a FAILURE, never a verdict, on the same principle as the 0-row guard.
  pdev, bdev = sorted(devnames(py)), sorted(devnames(bd))
  if pdev != bdev:
    print(f"# devices py={pdev} bend={bdev} -- NOT WELL-POSED, and this is NOT a verdict "
          f"(exit 2). The port's graph fixture is pinned at the arena tag 0 and the py graph "
          f"is on {pdev}, so every consumer of the ALLOC would carry a different `core` and "
          f"the report would be a cascade of `src` differences with the cause in none of "
          f"them. Re-run with --dev <the name the port resolved> -- or, if the name is not "
          f"in the port's table at all, that is a port gap to report, not a flag to set.",
          file=sys.stderr)
    return 2
  rc, txt = report(py, bd, a.plant, equiv=a.equiv)
  print("\n".join("# " + n for n in notes))
  print(txt)
  return rc


if __name__ == "__main__":
  sys.exit(main())