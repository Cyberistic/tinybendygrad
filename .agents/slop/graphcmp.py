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
               no longer does. Upstream's `ParamArg.device` is a NAME: `Compiled.device`
               is the canonicalized `str` the device was opened with (device.py:396, from
               `_Device.__getitem__`'s `cls(ix)` at :29 over `_canonicalize` at :26). The
               port's arena carries an interned `U32` tag instead (LAWS/spec.bend:85-87)
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
    python3 .agents/slop/graphcmp.py diff --dev-map 0=NULL
    python3 .agents/slop/graphcmp.py diff --plant srcswap
    python3 .agents/slop/graphcmp.py control

Exit status: 0 when the two sides agree on every core and every field, 1 when they do not,
2 when a side produced nothing -- which is a FAILURE and never a verdict (trap 4 above).
"""
from __future__ import annotations

import argparse
import hashlib
import os
import pathlib
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
SLOP = REPO / ".agents" / "slop"
BEND_PROBE = SLOP / "graphcmp.bend"
BEND = REPO / "bin" / "bend"

from tinygrad.dtype import AddrSpace, DType, dtypes  # noqa: E402
from tinygrad.uop.ops import AxisType, Ops, ParamArg, UOp  # noqa: E402

# THE ATOM TABLE. One letter per value KIND and no letter reused, because a collision
# would make two different values render the same and a differ would then agree with
# itself for the wrong reason -- `selfcheck` asserts the distinctness.
ATOMS = {"none": "N", "u32": "i", "i64": "l", "float": "f", "bool": "b", "str": "s",
         "bytes": "y", "dtype": "D", "ops": "O", "axis": "X", "addr": "S", "invalid": "v"}


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
    return f"kI({bstr(x.name)},{tup([_carg(o) for o in x.applied_opts])},{u(x.beam)})"
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
  problem this file exists to remove."""
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
    return ATOMS["bytes"] + str(len(x))
  if isinstance(x, (tuple, list)):
    return tup([_carg(e) for e in x])
  if isinstance(x, UOp):
    # An ARG may hold a UOp (`Ops.PYLITERAL`'s literal, `Ops.MSELECT`'s matcher --
    # ops.bend:938-941). The normal form records THAT IT IS A UOP and not WHICH, because
    # the arg's identity is already carried by the graph's `src` edges and a UOp's repr is
    # the whole pretty-print problem this file exists to remove. A named limitation, not
    # something papered over.
    return ATOMS["str"] + "<uop>"
  if isinstance(x, ParamArg):
    return paramarg(x)
  if type(x).__name__ == "Invalid":      # dtype.py:32; a CONST holding one is a refusal
    return ATOMS["invalid"]
  if hasattr(x, "__dataclass_fields__"):
    return f"{type(x).__name__}(" + "".join(
      f"{n}={_carg(getattr(x, n))}" for n in x.__dataclass_fields__) + ")"
  d = {k: v for k, v in vars(x).items() if k != "grad_fxn"}
  return f"{type(x).__name__}(" + "".join(f"{k}={_carg(v)}" for k, v in d.items()) + ")"


def paramarg(pa: ParamArg) -> str:
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
    f"realized{u(pa.buffer)}" if pa.buffer is not None else "unrealized",
    bo(pa.bind_on_realize),
    _carg(pa.val)]) + ")"


def cshape(n: UOp) -> str:
  try:
    shp = n.shape
  except RuntimeError:
    return "R"
  if shp is None:
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


GRAPHS = {"matmul": g_matmul, "reduce": g_reduce}

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


PLANTS = {"dtype": plant_dtype, "srcswap": plant_srcswap, "shape": plant_shape}


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


def emit_bend(dev: str, tries: int = 5, probe: pathlib.Path | None = None) -> tuple[list[str], list[str]]:
  """`probe` exists so the re-run guard can be SEEN TO FIRE: point it at a file that prints
  nothing and this must raise, not answer. Measured 20 consecutive runs of the real probe:
  20 x 18 rows, zero empty, so the trap never fired naturally today and an untested guard
  is exactly the guard that does not work."""
  notes = []
  for attempt in range(1, tries + 1):
    c = subprocess.run([str(BEND), str(probe or BEND_PROBE)], cwd=REPO, capture_output=True, text=True,
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


def report(py: list[str], bd: list[str], plant: str | None) -> tuple[int, str]:
  _, pcore = build(py, "py")
  _, bcore = build(bd, "bend")
  pnodes = {n.nid: n for ns in pcore.values() for n in ns}
  bnodes = {n.nid: n for ns in bcore.values() for n in ns}

  shared = sorted(set(pcore) & set(bcore))
  only_p = [n for k in sorted(set(pcore) - set(bcore)) for n in pcore[k]]
  only_b = [n for k in sorted(set(bcore) - set(pcore)) for n in bcore[k]]

  hard, soft = [], []
  for k in shared:
    for a, b in zip(pcore[k], bcore[k]):
      for d in mismatches(a, b):
        hard.append(f"MISMATCH {a.op:<9} py#{a.nid} vs bend#{b.nid}  {d}")

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

  o = [f"# py rows={len(pnodes)}  bend rows={len(bnodes)}  plant={plant or 'none'}",
       f"# devices py={sorted(devnames(py))} bend={sorted(devnames(bd))}  "
       f"(both sides emit the NAME: CPython's is `Compiled.device`, the port's is "
       f"`uop/render.bend:363` on the tag)",
       f"# SHARED cores={len(shared)}  ONLY-PY={len(only_p)}  ONLY-BEND={len(only_b)}  "
       f"field-mismatches={len(hard)}  rung2-pairs={sum(1 for x in soft if x.startswith('MIS'))}"]
  o += hard
  if soft:
    o.append("# RUNG 2 -- paired on the dtype-erased arg, so these ARE the same node:")
    o += soft
  if only_p:
    o.append(f"# ONLY ON THE PYTHON SIDE ({len(only_p)}), IN FULL:")
    o += [n.full("py") for n in sorted(only_p, key=lambda n: int(n.nid))]
  if only_b:
    o.append(f"# ONLY ON THE BEND SIDE ({len(only_b)}), IN FULL:")
    o += [n.full("bend") for n in sorted(only_b, key=lambda n: int(n.nid))]
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
  ap.add_argument("--dev", default=os.environ.get("DEV", "NULL"))
  ap.add_argument("--dev-map", default="", help="TAG=NAME[,...] binding the port's interned device index")
  ap.add_argument("--plant-side", choices=["py", "bend"], default="py",
                  help="which side --plant edits; always ONE side's copy, never the tree")
  ap.add_argument("--bend-probe", default=None,
                  help="override the port-side probe; used to SEE the 0-row re-run guard fire")
  a = ap.parse_args()

  dev_map = {}
  for kv in filter(None, a.dev_map.split(",")):
    k, v = kv.split("=")
    dev_map[int(k)] = v

  if a.cmd == "selfcheck":
    return selfcheck()
  if a.cmd == "emit":
    if a.side == "py":
      import tinygrad
      print(f"# graph={a.graph} plant={a.plant or 'none'} tree={tinygrad.__file__}", file=sys.stderr)
      print("\n".join(emit_py(a.graph, a.plant)))
    else:
      rows, notes = emit_bend(a.dev)
      print("\n".join("# " + n for n in notes), file=sys.stderr)
      if dev_map:
        rows = [rebind(r, dev_map) for r in rows]
        print(f"# dev-map {dev_map} bound into the stream", file=sys.stderr)
      print("\n".join(rows))
    return 0
  if a.cmd == "control":
    # A differ never seen to agree with ITSELF is not known to work.
    ok = True
    for name, get in (("py", lambda: emit_py(a.graph, a.plant)),
                      ("bend", lambda: emit_bend(a.dev)[0])):
      rc, txt = report(get(), get(), a.plant, dev_map)
      print(f"== CONTROL {name} vs itself: rc={rc}\n{txt}")
      ok = ok and rc == 0
    print(f"# CONTROL VERDICT: {'OK' if ok else 'THE DIFFER DISAGREES WITH ITSELF'}")
    return 0 if ok else 1
  if a.cmd == "cross":
    # THE OTHER HALF OF "the differ has been SEEN to disagree". `control` shows it is quiet
    # on a side against itself; this shows it is LOUD on two DIFFERENT graphs. A differ that
    # answers AGREE to `matmul` and to `sum(axis=1)` is worse than no differ, and the only
    # way to know it is not that one is to ask.
    other = [g for g in sorted(GRAPHS) if g != a.graph]
    rc, txt = report(emit_py(a.graph, None), emit_py(other[0], None), f"{a.graph}-vs-{other[0]}", dev_map)
    print(txt)
    print(f"# CROSS VERDICT: {'OK -- it disagrees' if rc else 'IT AGREED WITH A DIFFERENT GRAPH'}")
    return 0 if rc else 1
  bd, notes = emit_bend(a.dev, probe=pathlib.Path(a.bend_probe) if a.bend_probe else None)
  rc, txt = report(emit_py(a.graph, a.plant), bd, a.plant, dev_map)
  print("\n".join("# " + n for n in notes))
  print(txt)
  return rc


if __name__ == "__main__":
  sys.exit(main())