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
                  Buffer (render.py:159-160), so `buffer` reduces to `realized<slot>` /
                  `unrealized`: presence and slot are compared, the object is not.
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

USAGE

    python3 .agents/slop/graphcmp.py selfcheck
    python3 .agents/slop/graphcmp.py emit py   --graph matmul  > runs/graphcmp/py.txt
    python3 .agents/slop/graphcmp.py emit bend                  > runs/graphcmp/bend.txt
    python3 .agents/slop/graphcmp.py diff
    python3 .agents/slop/graphcmp.py diff --plant srcswap
    python3 .agents/slop/graphcmp.py control

There is no `--dev-map`. The device name is not bound at a prompt: the port resolves its
interned tag through its own table (R7) and both sides then carry a NAME.

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

REPO = pathlib.Path(__file__).resolve().parents[2]
SLOP = REPO / ".agents" / "slop"
BEND_PROBE = SLOP / "graphcmp.bend"
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
  globals().update(AddrSpace=dtm.AddrSpace, DType=dtm.DType, dtypes=dtm.dtypes,
                   AxisType=opm.AxisType, Ops=opm.Ops, ParamArg=opm.ParamArg, UOp=opm.UOp)


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


def chunk(s: str) -> str:
  """`<bytecount>:<bytes>` -- BYTES, because bytes are what the reader walks."""
  b = s.encode()
  if any(c > 127 for c in b):
    raise ValueError(f"non-ASCII in a normal-form chunk: {s!r}")
  return f"{len(b)}:{b.decode()}"


def unchunks(line: str) -> list[str]:
  """Walk the counts. Splitting on whitespace is what dropped 216 of 228 rows in the
  pin/HEAD study, because the row NAMES contain spaces."""
  out, i = [], 0
  while i < len(line):
    j = line.index(":", i)
    n, k = int(line[i:j]), j + 1
    out.append(line[k:k + n])
    i = k + n
    if i < len(line):
      if line[i] != " ":
        raise ValueError(f"chunks not space-separated at {i}: {line[max(0, i - 10):i + 10]!r}")
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
    ids, k = x[1:], 0
    while isinstance(ids, tuple):
      ids, k = ids[0], k + 1
    return f"rg({u(k)},{ATOMS['axis']}{x[0].name},{tup([u(i) for i in (x[1:] if k else (x[1],))])})"
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

  THE ENUM ARM IS NOT COSMETIC. Before it, `enum.Enum` fell through to the `vars()`
  arm below, and MEASURED `vars(OptOps.TC)` raises
  `TypeError: vars() argument must have __dict__ attribute` on 3.12 -- an enum MEMBER has
  no `__dict__`, so `vars` is right to refuse (`getattr(m, "__dict__")` only appears to
  work because it falls back to the CLASS's dict). So `carg(Ops.SINK, <a KernelInfo with
  a non-empty applied_opts>)` DIED with a traceback: a kernelized graph could not be
  emitted at all, and the residual was reported as "an Option dataclass the port cannot
  read" when the honest answer was "this emitter raises". `Ops`, `AxisType` and
  `AddrSpace` are matched by exact type above, so this arm is the one that catches
  `OptOps` (codegen/opt/__init__.py:6) and anything a later commit adds. The member's
  `name` is its identity -- `list(OptOps)` is TC/SPLIT/PADTO/SWAP and `name` is unique per
  member -- so `name` is what is compared and `value` is not."""
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
    # LENGTH only, and so does the port (ops.bend:913: "bytes BINARY arg; only its length
    # is read"). Comparing the content would be a field the port can never fill, and
    # comparing the length is a real comparison both sides can make.
    #
    # NOT NEUTRAL, and the ledger says so on every report. MEASURED, both sides:
    #   upstream `UOp(Ops.BINARY, (), b"aaaa")` and `..., b"bbbb")` are DIFFERENT objects
    #   with different keys, and the port interns the SAME arena node for the two
    #   (index 1 twice, `Arena.next` 2). So the loss is not "we compare less than the
    #   printer would": the port's IDENTITY does not see the bytes, and two graphs that
    #   upstream calls different this gate can only report as equal. See `--plant bytes`.
    return ATOMS["bytes"] + str(len(x))
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


def cdepth(n: UOp) -> int:
  """R5. Only a RANGE's `axis_id` can nest (`UOp.range`, ops.py:643); `UOp.new` stores 0 for
  everything else (ops.bend:1097)."""
  if n.op is not Ops.RANGE:
    return 0
  ids, k = n.arg[1:], 0
  while isinstance(ids, tuple):
    ids, k = ids[0], k + 1
  return k


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


GRAPHS = {"matmul": g_matmul, "reduce": g_reduce, "buffer": g_buffer, "sink": g_sink}

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
    self.kidop: dict[str, str] = {}
    self.side = ""

  def __repr__(self) -> str:
    return f"<{self.op}#{self.nid}>"

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
    return (f"{self.op}\x00{self.depth}\x00{self.tag}\x00{erase(self.arg)}\x00"
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
  ("y", 6, "a bytes arg: LENGTH only",
   "upstream gives two same-length blobs different keys; the port interns them as ONE "
   "node (measured) -- this is a port IDENTITY divergence, not only a normal-form loss"),
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
   "`OptOps` (codegen/opt/__init__.py:6). Before the enum arm this CRASHED: `vars()` "
   "raises on an enum member, so a SINK with a non-empty applied_opts could not be "
   "emitted at all"),
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


def build(lines: list[str], side: str) -> tuple[dict[str, Node], dict[str, Node]]:
  """(nodes by id, nodes by core). The core is computed from the CHILDREN's cores, so the
  walk is a topological one; `order` is derived here rather than trusted from the emitter,
  and a cycle is a loud failure instead of a recursion."""
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
  node, bycore, done, order, path = {}, {}, set(), [], set()

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
      n.kidop[c] = node[c].op
    n.core = hashlib.sha256((f"{n.op}\x00{n.depth}\x00{n.tag}\x00{n.arg}\x00"
                             + "|".join(n.cores[c] for c in kids[nid])).encode()).hexdigest()
    bycore.setdefault(n.core, []).append(n)

  for nid in recs:
    go(nid)
  return node, bycore


FIELDS = ("dtype", "shape", "depth", "tag", "arg", "src")


def mismatches(a: Node, b: Node) -> list[str]:
  """NAMES the fields that differ, never a count. `src` is compared as the ordered list of
  the two sides' CORE keys, so a swap reads as an `src` difference on the PARENT and as
  nothing at all on the children -- the property `--plant srcswap` exists to show."""
  out = []
  for f in FIELDS:
    if f == "src":
      if [a.cores[c] for c in a.src] != [b.cores[c] for c in b.src]:
        out.append(f"src  py={[a.cores[c][:8] for c in a.src]} bend={[b.cores[c][:8] for c in b.src]}")
    elif getattr(a, f) != getattr(b, f):
      out.append(f"{f:<5} py={getattr(a, f)} bend={getattr(b, f)}")
  return out


def report(py: list[str], bd: list[str], plant: str | None,
           lname: str = "py", rname: str = "bend") -> tuple[int, str]:
  """`lname`/`rname` label the two sides in every line they appear in. They are PARAMETERS,
  not the literals "py"/"bend", because MEASURED: hardcoding them made `cross` and `control`
  -- which deliberately compare a side against ITSELF and one graph against another -- print
  "ONLY ON THE PYTHON SIDE" for nodes that are only on the BEND side. A wrong label in a
  report is not cosmetic here: `cross` is the check that decides whether the differ can see
  a difference at all, and a reader who is told the wrong side sent a node stops trusting
  the rest of the block. Defaulted to the two real sides so every existing call is unchanged.
  """
  _, pcore = build(py, lname)
  _, bcore = build(bd, rname)
  pnodes = {n.nid: n for ns in pcore.values() for n in ns}
  bnodes = {n.nid: n for ns in bcore.values() for n in ns}

  shared = sorted(set(pcore) & set(bcore))
  only_p = [n for k in sorted(set(pcore) - set(bcore)) for n in pcore[k]]
  only_b = [n for k in sorted(set(bcore) - set(pcore)) for n in bcore[k]]

  hard, soft = [], []
  for k in shared:
    for a, b in zip(pcore[k], bcore[k]):
      for d in mismatches(a, b):
        hard.append(f"MISMATCH {a.op:<9} {lname}#{a.nid} vs {rname}#{b.nid}  {d}")

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
    scored = sorted(((len(mismatches(a, b)), b) for b in cands), key=lambda p: (p[0], p[1].nid))
    if len(scored) > 1 and scored[0][0] == scored[1][0]:
      continue                              # ambiguous: no mutual best, so no claim
    pairs.append((a, scored[0][1]))
    taken_b.add(id(scored[0][1]))
  for a, b in pairs:
    soft.append(f"MISMATCH {a.op:<9} py#{a.nid} vs {b.side}#{b.nid}  (no shared core; paired "
                f"one-to-one on the dtype-erased arg)")
    soft += ["    " + d for d in mismatches(a, b)]
  only_p = [n for n in only_p if not any(n is a for a, _ in pairs)]
  only_b = [n for n in only_b if id(n) not in taken_b]

  o = [f"# {lname} rows={len(pnodes)}  {rname} rows={len(bnodes)}  plant={plant or 'none'}",
       f"# devices {lname}={sorted(devnames(py))} {rname}={sorted(devnames(bd))}  "
       f"(both sides emit the NAME: CPython's is `Compiled.device`, the port's is "
       f"`uop/render.bend:363` on the tag)"]
  o += residual_lines(ledger(py), ledger(bd))
  o += [f"# SHARED cores={len(shared)}  ONLY-{lname.upper()}={len(only_p)}  "
        f"ONLY-{rname.upper()}={len(only_b)}  "
        f"field-mismatches={len(hard)}  rung2-pairs={sum(1 for x in soft if x.startswith('MIS'))}"]
  o += hard
  if soft:
    o.append("# RUNG 2 -- paired on the dtype-erased arg, so these ARE the same node:")
    o += soft
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
  print("# SELFCHECK: " + ("OK" if not bad else "FAIL"))
  for b in bad:
    print("#   " + b)
  return 0 if not bad else 1


def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("cmd", choices=["emit", "diff", "control", "cross", "selfcheck"])
  ap.add_argument("--graph", choices=sorted(GRAPHS), default="matmul")
  ap.add_argument("--side", choices=["py", "bend"], default="py")
  ap.add_argument("--plant", choices=sorted(PLANTS), default=None)
  # CPU, NOT `os.environ.get("DEV")`. The port's graph fixture pins the ALLOC device at
  # tag 0, which `uop/render.bend:361` names CPU and `schedule/__init__.bend:1095` says so
  # in words; upstream's default device is whichever of `ALL_DEVICES` opens first
  # (device.py:55-58), which is METAL on this machine and NULL under `DEV=NULL`, so an
  # inherited DEV silently compares the port's CPU graph against a different device. The
  # comparison is only well-posed at a PINNED device, and CPU is the one tag 0 names.
  ap.add_argument("--dev", default="CPU")
  ap.add_argument("--plant-side", choices=["py", "bend"], default="py",
                  help="which side --plant edits; always ONE side's copy, never the tree")
  ap.add_argument("--bend-probe", default=None,
                  help="override the port-side probe; used to SEE the 0-row re-run guard fire")
  a = ap.parse_args()
  # ONE `--dev` GOVERNS BOTH SIDES, and it must be in the environment before tinygrad is
  # imported (`load` above). `clean_env` then hands the same value to the bend child.
  os.environ["DEV"] = a.dev
  load_tinygrad()

  if a.cmd == "selfcheck":
    return selfcheck()
  if a.cmd == "emit":
    if a.side == "py":
      import tinygrad
      print(f"# graph={a.graph} plant={a.plant or 'none'} tree={tinygrad.__file__}", file=sys.stderr)
      print("\n".join(emit_py(a.graph, a.plant)))
    else:
      rows, notes = emit_bend(a.dev, a.graph)
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
      rc, txt = report(get(), get(), a.plant, name, name)
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
  rc, txt = report(py, bd, a.plant)
  print("\n".join("# " + n for n in notes))
  print(txt)
  return rc


if __name__ == "__main__":
  sys.exit(main())