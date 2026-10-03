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
              (`H.i64_text`, helpers.bend:1227, is two words for exactly this) and a UOp
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
         "bytes": "y", "dtype": "D", "ops": "O", "axis": "X", "addr": "S", "invalid": "v",
         "devex": "t"}


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
  """`hi:lo`, exactly `H.i64_text` (helpers.bend:1227). A dim is an I64 and dropping the
  high word would read a dimension of 2**32 as zero."""
  return ATOMS["i64"] + f"{x >> 32:x}:{x & 0xFFFFFFFF:x}"


def tup(xs) -> str:
  return "n(" + ",".join(xs) + ")"


def bstr(s: str) -> str:
  return ATOMS["str"] + s


def bo(x) -> str:
  return ATOMS["bool"] + ("1" if x else "0")


def dt(d: DType) -> str:
  return ATOMS["dtype"] + d.name


def dev(x) -> str:
  """The port's `S.D1{tag}` is an INTERNED INDEX, not a name: schedule/__init__.bend:1095
  says tag 0 is CPU, schedule/memory.bend:998-999 says 0 is CPU and 1 is DISK, and
  device.bend:702 says 7 is CPU and 11 is NULL -- three tables and no reader from a tag to
  a name. CPython's value IS a name (`tinygrad/device.py`), so this side emits
  `s<NAME>` and `--dev-map` is what binds the two. Unbound is reported, never guessed."""
  if x is None:
    return ATOMS["none"]
  return ATOMS["str"] + ",".join(x) if isinstance(x, tuple) else bstr(str(x))


def carg(x) -> str:
  """R7, CPython side. Mirrors `argstr` in graphcmp.bend character for character."""
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
    return ATOMS["bytes"] + x.hex()
  if isinstance(x, (tuple, list)):
    return tup([carg(e) for e in x])
  if isinstance(x, UOp):
    return f"{ATOMS['str']}uop"          # `Ops.NOOP`'s `src` may carry a UOp (ops.bend:838)
  if isinstance(x, ParamArg):
    return paramarg(x)
  if type(x).__name__ == "Invalid":      # dtype.py:32; a CONST holding one is a refusal
    return ATOMS["invalid"]
  if hasattr(x, "__dataclass_fields__"):
    return f"{type(x).__name__}(" + "".join(
      f"{n}={carg(getattr(x, n))}" for n in x.__dataclass_fields__) + ")"
  # `CallInfo` (ops.py:1400) and `KernelInfo` (ops.py:1339) are plain classes with
  # class-level defaults, so `__dataclass_fields__` does not exist and the instance dict is
  # the field list -- in DECLARATION order, because CPython dicts are ordered. `grad_fxn`
  # is an `id()` upstream prints verbatim (ops.py:1409) and is dropped: a per-process
  # address is not reproducible, and it is dropped on BOTH sides, not compared.
  d = {k: v for k, v in vars(x).items() if k != "grad_fxn"}
  return f"{type(x).__name__}(" + "".join(f"{k}={carg(v)}" for k, v in d.items()) + ")"


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
    carg(pa.val)]) + ")"


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


def row_of(n: UOp, k: int) -> str:
  return " ".join(chunk(v) for v in [u(k), n.op.name, n.dtype.name, cshape(n), u(cdepth(n)),
                                     ctag(n.tag), carg(n.arg), tup([u(s) for s in n.src])])


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


def plant_dtype(ast: UOp) -> UOp:
  """Change the two ALLOCs and everything downstream of them to int32. MUL and ADD are
  commutative and `promo_dtype` handles an int/f32 mix, so the SHAPE of the MUL changes
  too -- which is the point: the differ must name `dtype`, not stop at "a node differs".
  Every op, arg, depth, tag, child count and child order is untouched."""
  def alloc(a):
    return UOp(Ops.ALLOC, src=(), arg=ParamArg(a.arg.slot, dtypes.int, a.arg.size,
                                               device=a.arg.device, bind_on_realize=True))
  mul = ast.src[0]
  a, b = mul.src
  assert a.src[0].op is Ops.ALLOC and b.op is Ops.ALLOC, "plant targets the two ALLOCs"
  aa, sh_a, sh_a2 = alloc(a.src[0]), a.src[1], a.src[1]
  bb, sh_b = alloc(b.src[0]), a.src[1].src[1].src[1]
  r_a = UOp(Ops.RESHAPE, src=(aa, sh_a))
  r_a2 = UOp(Ops.RESHAPE, src=(r_a, sh_a2))
  r_b = UOp(Ops.RESHAPE, src=(bb, sh_b))
  r_b2 = UOp(Ops.RESHAPE, src=(r_b, mul.src[1].src[0].src[1]))
  p0 = UOp(Ops.PERMUTE, src=(r_b2,), arg=(0, 2, 1))
  return UOp(Ops.REDUCE, src=(UOp(Ops.PERMUTE, src=(UOp(Ops.MUL, src=(r_a2, p0)),), arg=(2, 0, 1)),),
             arg=(Ops.ADD, 1))


def plant_srcswap(ast: UOp) -> UOp:
  """Swap the two children of the MUL. MUL is commutative in tinygrad, so this is a
  SEMANTIC no-op -- which is exactly why a differ that only counted nodes would miss it.
  Nothing else is touched, so the report must be the swapped pair ALONE: the reordered
  pair's own fields must not be flagged."""
  m = ast.src[0]
  assert m.op is Ops.MUL, "plant targets the MUL"
  sw = UOp(Ops.MUL, src=(m.src[1], m.src[0]))
  return UOp(Ops.REDUCE, src=(UOp(Ops.PERMUTE, src=(sw,), arg=(2, 0, 1)),), arg=(Ops.ADD, 1))


PLANTS = {"dtype": plant_dtype, "srcswap": plant_srcswap}


def emit_py(graph: str, plant: str | None) -> list[str]:
  """The CPython side. A plant edits THIS SIDE'S COPY and nothing else -- never the live
  tree, never a port file. 400 oracles under `.agents/slop/` mutate a COPY for the same
  reason."""
  ast = GRAPHS[graph]()
  if plant:
    ast = PLANTS[plant](ast)
  return [row_of(n, i) for i, n in enumerate(ast.toposort())]


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


def emit_bend(dev: str, tries: int = 5) -> tuple[list[str], list[str]]:
  notes = []
  for attempt in range(1, tries + 1):
    c = subprocess.run([str(BEND), str(BEND_PROBE)], cwd=REPO, capture_output=True, text=True,
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

  def __init__(self, f: list[str]):
    self.nid, self.op, self.dtype, self.shape, self.depth, self.tag, self.arg, self.src = f
    self.cores: dict[str, str] = {}

  def __repr__(self) -> str:
    return f"<{self.op}#{self.nid}>"

  @property
  def loose(self) -> str:
    """Rung 2. The arg with every dtype SPEL erased, plus the children's OPS rather than
    their cores -- so a node whose only difference is a dtype finds a partner and the
    difference is reported as the `dtype` field."""
    return (f"{self.op}\x00{self.depth}\x00{self.tag}\x00{erase(self.arg)}\x00"
            + ",".join(self.kid_ops[c] for c in self.src))

  def full(self, side: str) -> str:
    return (f"  {side}#{self.nid} {self.op} dtype={self.dtype} shape={self.shape} "
            f"depth={self.depth} tag={self.tag} arg={self.arg} src={self.src}")


def erase(arg: str) -> str:
  """`D<name>` -> `D*`. Exhaustive by construction: a dtype appears in the normal form
  ONLY as `D<name>`, so one pass cannot miss a spelling."""
  out, i = [], 0
  while i < len(arg):
    if arg.startswith(ATOMS["dtype"], i):
      j = arg.find(")", i)
      if j != -1 and not set(",()") & set(arg[i + 1:j]):
        out.append(ATOMS["dtype"] + "*")
        i = j
        continue
    out.append(arg[i])
    i += 1
  return "".join(out)


def devtags(arg: str) -> set[int]:
  """The `t<n>` device tags in an arg text. Unbound until `--dev-map` names them, and
  reported as unbound rather than silently compared as integers."""
  out, i = set(), 0
  while i < len(arg):
    if arg[i] == ATOMS["devex"] and arg[i + 1:i + 2].isdigit():
      j = i + 1
      while arg[j:j + 1].isdigit():
        j += 1
      out.add(int(arg[i + 1:j]))
      i = j
    else:
      i += 1
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
  node, bycore, done, stack = {}, {}, set(), []

  def go(nid):
    if nid in done:
      return
    if nid in stack:
      raise SystemExit(f"{side}: CYCLE at node {nid}")
    stack.add(nid)
    for c in kids[nid]:
      go(c)
    stack.discard(nid)
    done.add(nid)
    stack.append(nid)
    f = recs[nid]
    n = Node(f)
    node[nid] = n
    for c in kids[nid]:
      n.cores[c] = node[c].core
    n.kid_ops = {c: node[c].op for c in kids[nid]}
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


def group_loose(ns: list[Node]) -> dict[str, list[Node]]:
  out: dict[str, list[Node]] = {}
  for n in ns:
    out.setdefault(n.loose, []).append(n)
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

  lp, lb = group_loose(only_p), group_loose(only_b)
  for k in sorted(set(lp) & set(lb)):
    for a in lp[k]:
      for b in lb[k]:
        soft.append(f"MISMATCH {a.op:<9} py#{a.nid} vs bend#{b.nid}  (no shared core)")
        soft += ["    " + d for d in mismatches(a, b)]
    only_p = [n for n in only_p if n.loose != k]
    only_b = [n for n in only_b if n.loose != k]

  tags = sorted(t for n in list(pnodes.values()) + list(bnodes.values()) for t in devtags(n.arg))
  o = [f"# py rows={len(pnodes)}  bend rows={len(bnodes)}  plant={plant or 'none'}",
       f"# SHARED cores={len(shared)}  ONLY-PY={len(only_p)}  ONLY-BEND={len(only_b)}  "
       f"field-mismatches={len(hard)}  rung2-pairs={len(soft) // 2}"]
  if tags:
    o.append(f"# UNBOUND-DEVTAG {tags} -- the port emits an INTERNED INDEX and CPython emits "
             f"a NAME; pass --dev-map 0=NAME to bind it.")
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
  ap.add_argument("cmd", choices=["emit", "diff", "control", "selfcheck"])
  ap.add_argument("--graph", choices=sorted(GRAPHS), default="matmul")
  ap.add_argument("--side", choices=["py", "bend"], default="py")
  ap.add_argument("--plant", choices=sorted(PLANTS), default=None)
  ap.add_argument("--dev", default=os.environ.get("DEV", "NULL"))
  ap.add_argument("--dev-map", default="", help="TAG=NAME[,...] binding the port's interned device index")
  a = ap.parse_args()

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
      print("\n".join(rows))
    return 0
  if a.cmd == "control":
    # A differ never seen to agree with ITSELF is not known to work.
    ok = True
    for name, get in (("py", lambda: emit_py(a.graph, a.plant)),
                      ("bend", lambda: emit_bend(a.dev)[0])):
      rc, txt = report(get(), get(), a.plant)
      print(f"== CONTROL {name} vs itself: rc={rc}\n{txt}")
      ok = ok and rc == 0
    print(f"# CONTROL VERDICT: {'OK' if ok else 'THE DIFFER DISAGREES WITH ITSELF'}")
    return 0 if ok else 1
  bd, notes = emit_bend(a.dev)
  rc, txt = report(emit_py(a.graph, a.plant), bd, a.plant)
  print("\n".join("# " + n for n in notes))
  print(txt)
  return rc


if __name__ == "__main__":
  sys.exit(main())