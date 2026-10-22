#!/usr/bin/env python3
"""ew_activation-compare.py -- THE THIRD LANE: the canonical graph diff, and the VALUE.

    .venv/bin/python gates/ew_activation-compare.py <port-rows> <cpython-rows>

IT ANSWERS TWO QUESTIONS AND BOTH ARE MEASUREMENTS.

  1. DOES THE PORT BUILD THE SAME GRAPH?  The two lanes' graphs are put in the SAME
     CANONICAL FORM -- a bottom-up `(op, dtype, arg, srcs...)` tuple -- and compared.
     CANONICAL, and not positional, because the port's node ids are ARENA INDICES and
     CPython's are TOPOSORT POSITIONS: the ids are different numberings of the same
     shape, so a line-for-line diff of the ids would be a diff of two numbering
     conventions.  The canonical form has no ids in it at all.

  2. WHAT IS THE PORT'S VALUE?  THE PORT'S OWN DUMP IS REBUILT AS tinygrad UOps AND
     REALIZED, so the number compared against CPython's is the value of the graph THE
     PORT BUILT and not the value of CPython's graph read back.  That is the whole
     point of the rebuild: `gates/tn_bitwise_not-oracle.py`'s post-mortem is for an
     oracle that HAND-BUILDS the thing it is checking -- an oracle that re-implements
     `Tensor.asin` agrees with a port that is ITSELF wrong.

THE REBUILD IS CHECKED AGAINST SOMETHING THAT IS NOT ITSELF.  Before the port's graph
is rebuilt, CPython's OWN graph is rebuilt from CPython's OWN dump and its value is
compared with the value CPython measured directly.  A harness whose parser or whose
UOp construction is wrong fails THERE, before any disagreement it might report about
the port is worth reading.  That check is the selfcheck and it is not optional.

THE CONSTANTS ARE COMMITTED AT `float32` ON BOTH LANES, AND THAT LOOKS WRONG ON THE
PYTHON DEVICE.  **DO NOT "FIX" IT.**  Upstream's `asin` names `math.pi / 2`, a DOUBLE;
the port has no F64 and names `f32(math.pi / 2)`.  MEASURED: with the constant left
in DOUBLE the two differ by EXACTLY ONE ULP at some inputs -- `atan` at x = +-1 and
+-3, which is 29 of the 255 rows on the double-precision PYTHON device -- and
swapping the constant's value in CPython's OWN graph is what moves it.  MEASURED TOO:
tinygrad's own generated float32 kernel writes `1.5707963705062866f` -- the f32-exact
value with an `f` suffix -- so on a REAL float32 device upstream's constant and the
port's are THE SAME NUMBER.  The comparison therefore commits the weak float
constants at `float32` on BOTH lanes, which is what a float32 device does, and the
`29 of 255` is a measurement of the PYTHON DEVICE and not of the port.  The same
reasoning is in `gates/decomp_value-gate.py`, which has the tree's other `commit()`.

EXIT STATUS: 0 every graph matched and every value matched, 1 something did not, 3 a
precondition was absent (a lane produced no rows, or the rebuild failed its selfcheck).

THE LAST LINE IS `SUMMARY key=value ...`, and it is the ONLY line a caller parses:
the prose above it is for a reader and the summary is for the gate.  A gate that
counts sentences is a gate that reads a comment.
"""
import re
import struct
import sys

from tinygrad.dtype import dtypes
from tinygrad.tensor import Tensor
from tinygrad.uop.ops import Ops, UOp

# THE DTYPES THE PORT NAMES.  CPython's dtype NAMES -> THE PORT's (`LAWS/spec.bend`'s).
DT = {"f32": dtypes.float32, "f16": dtypes.float16, "f64": dtypes.float64,
      "bool": dtypes.bool, "weakint": dtypes.weakint, "weakfloat": dtypes.weakfloat,
      "i32": dtypes.int32, "i8": dtypes.int8, "u8": dtypes.uint8,
      "i64": dtypes.int64, "u32": dtypes.uint32}
DTNAME = {"float32": "f32", "float16": "f16", "float64": "f64", "int32": "i32",
          "int8": "i8", "uint8": "u8", "int64": "i64", "uint32": "u32", "bool": "bool",
          "weakint": "weakint", "weakfloat": "weakfloat"}
# THE OPS THE ACTIVATIONS AND `relu` USE.  A NODE WHOSE OP IS NOT HERE IS A ROW
# THAT FAILED LOUDLY, NOT A ROW THAT WAS SKIPPED.
UNARY = {"SQRT": Ops.SQRT, "LOG2": Ops.LOG2, "EXP2": Ops.EXP2, "RECIPROCAL": Ops.RECIPROCAL,
         "SIN": Ops.SIN, "NEG": Ops.NEG, "TRUNC": Ops.TRUNC}
BINARY = {"ADD": Ops.ADD, "MUL": Ops.MUL, "SUB": Ops.SUB, "MAX": Ops.MAX,
          "CMPLT": Ops.CMPLT, "CMPNE": Ops.CMPNE, "POW": Ops.POW, "CDIV": Ops.CDIV}

SUMMARY = re.compile(r"^SUMMARY (.*)$", re.M)


def f32bits(x) -> int:
  return struct.unpack("I", struct.pack("f", float(x)))[0]


def frombits(b: int) -> float:
  return struct.unpack("f", struct.pack("I", b))[0]


def i64words(v: int) -> str:
  """`hi:lo`, the port's own `H.i64_text` spelling -- two UNSIGNED words, so a value
  never has to leave U32 to be read."""
  return f"{(v >> 32) & 0xFFFFFFFF}:{v & 0xFFFFFFFF}"


def i64value(s: str) -> int:
  hi, lo = (int(x) for x in s.split(":"))
  v = (hi << 32) | lo
  return v - (1 << 64) if hi >= (1 << 31) else v


def dtname(dt) -> str:
  return DTNAME.get(dt.name, dt.name)


def argstr(u: UOp) -> str:
  if u.op is Ops.CONST:
    v = u.arg
    if isinstance(v, bool):
      return "cb:" + ("True" if v else "False")
    if isinstance(v, int):
      return "ci:" + i64words(v)
    return "cf:" + str(f32bits(float(v)))
  if u.op is Ops.CAST:
    return "dt:" + dtname(u.arg)
  return "-"


# ---------------------------------------------------------------- the CPython lane
def cpython_dump(u: UOp) -> dict:
  """`{id: (op, dtype, arg, [src ids])}` over CPython's toposort, with the ids being
  the TOPOSORT POSITIONS."""
  ts = list(u.toposort())
  out = {}
  for i, x in enumerate(ts):
    out[i] = (x.op.name, dtname(x.dtype), argstr(x), [ts.index(s) for s in x.src])
  return out


def canonical(nodes: dict, root: int) -> tuple:
  """THE CANONICAL FORM: a bottom-up `(op, dtype, arg, srcs...)` tuple with NO IDS.

  It is computed over the ids in ascending order, which is a valid build order for
  both lanes: the port's arena is APPEND-ONLY and `UOp.make` only ever interns a node
  whose srcs are already in the arena, so a src's id is BELOW its consumer's.
  """
  memo = {}

  def go(i):
    if i in memo:
      return memo[i]
    op, dt, arg, srcs = nodes[i]
    c = (op, dt, arg, tuple(go(s) for s in srcs))
    memo[i] = c
    return c

  return go(root)


# ---------------------------------------------------------------- the port's lane
def parse_port(path):
  """The port's dump, grouped by the `M` header.  Each group is
  `(name, alpha, gamma, fixture_bits, root, {id: (op, dtype, arg, [src ids])})`."""
  groups, cur, root = [], None, None
  for line in open(path).read().splitlines():
    if not line:
      continue
    if line.startswith("M "):
      _, nm, alpha, gamma, fx = line.split(" ")
      cur = (nm, alpha, gamma, fx, None, {})
      groups.append(cur)
      root = None
    elif line.startswith("R "):
      root = int(line.split(" ")[1])
      cur = (cur[0], cur[1], cur[2], cur[3], root, cur[5])
      groups[-1] = cur
    elif line.startswith("V "):
      continue
    else:
      f = line.split(" ")
      i = int(f[0])
      srcs = [int(x) for x in f[4:] if x != ""]
      cur[5][i] = (f[1], f[2], f[3], srcs)
  return groups


def build_port(nodes: dict, root: int) -> UOp:
  """THE PORT'S GRAPH, REBUILT AS tinygrad UOps.  THE IDS ARE THE PORT'S OWN, so the
  rebuild needs no renumbering -- it is the port's graph, node for node."""
  made = {}
  for i in sorted(nodes):
    op, dt, arg, srcs = nodes[i]
    s = [made[x] for x in srcs]
    if op == "CONST":
      if arg.startswith("cf:"):
        u = UOp.const(frombits(int(arg[3:])), DT[dt])
      elif arg.startswith("ci:"):
        u = UOp.const(i64value(arg[3:]), DT[dt])
      elif arg.startswith("cb:"):
        u = UOp.const(arg[3:] == "True", DT[dt])
      else:
        raise ValueError(f"unknown const arg {arg!r}")
    elif op == "CAST":
      if not arg.startswith("dt:"):
        raise ValueError(f"unknown cast arg {arg!r}")
      u = UOp(Ops.CAST, src=(s[0],), arg=DT[arg[3:]])
    elif op == "WHERE":
      u = UOp(Ops.WHERE, src=tuple(s))
    elif op in UNARY:
      u = UOp(UNARY[op], src=tuple(s))
    elif op in BINARY:
      u = UOp(BINARY[op], src=tuple(s))
    else:
      raise ValueError(f"unknown op {op!r}")
    made[i] = u
  return made[root]


def value_of(u: UOp) -> float:
  return float(Tensor(u, device="PYTHON").numpy().reshape(-1)[0])


def commit(root: UOp) -> UOp:
  """THE WEAK FLOAT CONSTANTS COMMITTED AT `float32`, TO FIXPOINT.

  `gates/decomp_value-gate.py` has the tree's own `commit()` for the SAME reason
  this file needs one: a WEAK float constant carries a DOUBLE value, and the
  arithmetic then uses it at DOUBLE precision.  Upstream's `asin` names
  `math.pi / 2`, a DOUBLE; the port has no F64 and names `f32(math.pi / 2)`.

  **THIS IS WHAT MAKES THE TWO LANES COMPARABLE, AND IT IS NOT A CONVENIENCE.**
  MEASURED on CPython: with the constant left in DOUBLE, the port's constant and
  upstream's differ by EXACTLY ONE ULP at some inputs -- `atan` at x = +-1 and +-3,
  29 of 255 rows on the PYTHON device -- and swapping the constant's value in
  CPython's OWN graph is what moves it.  Committing the weak float constant at
  `float32` TRUNCATES it (`ccast` rebuilds a CONST as `UOp.const(dt.const(s.val))`,
  and `float32.const` truncates), which is EXACTLY the port's spelling AND exactly
  what a real float32 device does with upstream's constant: MEASURED, tinygrad's own
  generated kernel writes `1.5707963705062866f` -- the f32-exact value with an `f`
  suffix -- so upstream's DOUBLE constant and the port's F32 constant are THE SAME
  NUMBER ON AN f32 DEVICE.

  ONLY THE WEAK FLOAT CONSTANTS ARE COMMITTED: a weakint or a weakbool constant is
  not a float and committing it at `float32` would turn the `True` of a `CMPNE`
  into `1.0`.

  THE COMMIT IS APPLIED IDENTICALLY TO BOTH LANES, so it cannot manufacture a
  disagreement between them.
  """
  for _ in range(8):
    memo = {}

    def go(v):
      if id(v) in memo:
        return memo[id(v)]
      srcs = tuple(go(s) for s in v.src)
      u = UOp(v.op, srcs, v.arg, v.tag) if srcs != v.src else v
      if any(s.op is Ops.CONST and s.dtype is dtypes.weakfloat for s in u.src):
        u = u.replace(src=tuple(s.ccast(dtypes.float32) if s.op is Ops.CONST and s.dtype is dtypes.weakfloat
                                else s for s in u.src))
      memo[id(v)] = u
      return u

    nxt = go(root)
    if nxt is root or nxt == root:
      return nxt
    root = nxt
  return root


def committed_value(u: UOp) -> float:
  return value_of(commit(u))


def cpython_method(t: Tensor, name: str, alpha, gamma):
  """THE CPython METHOD, CALLED WITH THE PORT'S PARAMETERS."""
  a = frombits(int(alpha)) if alpha != "-" else None
  g = frombits(int(gamma)) if gamma != "-" else None
  if name == "asin":
    return t.asin()
  if name == "acos":
    return t.acos()
  if name == "atan":
    return t.atan()
  if name in ("elu", "elu_alpha"):
    return t.elu(a)
  if name in ("celu", "celu_alpha"):
    return t.celu(a)
  if name in ("selu", "selu_alpha"):
    return t.selu(a, g)
  if name == "relu":
    return t.relu()
  if name == "sigmoid":
    return t.sigmoid()
  if name == "tanh":
    return t.tanh()
  if name == "quick_gelu":
    return t.quick_gelu()
  if name == "swish":
    return t.swish()
  if name == "silu":
    return t.silu()
  raise KeyError(name)


def short(c) -> str:
  return repr(c)[:300]


def main(argv):
  if len(argv) != 3:
    print("usage: ew_activation-compare.py <port-rows> <cpython-rows>", file=sys.stderr)
    return 3
  pgroups = parse_port(argv[1])
  cgroups = parse_port(argv[2])
  print(f"port graph rows={len(pgroups)}  cpython graph rows={len(cgroups)}")
  if not pgroups or not cgroups:
    print("REFUSED: a lane produced no rows")
    return 3
  if len(pgroups) != len(cgroups):
    print("REFUSED: the lanes disagree on the row COUNT, so a row-by-row diff would be a comparison of different questions")
    return 3
  # 1. THE CANONICAL GRAPH DIFF.
  bad = []
  for (p, c) in zip(pgroups, cgroups):
    if tuple(p[:4]) != tuple(c[:4]):
      bad.append((p[0], p[3], "HEADER", " ".join(p[:4]), " ".join(c[:4])))
      continue
    pc = canonical(p[5], p[4])
    cc = canonical(c[5], c[4])
    if pc != cc:
      bad.append((p[0], p[3], "GRAPH", short(pc), short(cc)))
  print(f"graph rows compared={len(pgroups)}  graph rows differing={len(bad)}")
  for nm, fx, what, a, b in bad[:4]:
    print(f"  {what} {nm}@{fx}")
    print(f"    port   : {a[:300]}")
    print(f"    cpython: {b[:300]}")
  # 2. THE SELFCHECK: CPython's OWN graph, REBUILT FROM CPython's OWN DUMP, must give
  # CPython's OWN value.  A harness whose parser or whose UOp construction is wrong
  # fails HERE, before any disagreement it might report about the port is worth
  # reading.  IT IS NOT OPTIONAL.
  sc, scv = 0, 0
  for c in cgroups:
    t = Tensor(UOp.const(frombits(int(c[3])), dtypes.weakfloat), device="PYTHON")
    cm = cpython_method(t, c[0], c[1], c[2])
    want = committed_value(cm._uop)
    got = committed_value(build_port(c[5], c[4]))
    if f32bits(got) != f32bits(want):
      sc += 1
      if sc <= 3:
        print(f"  SELFCHECK {c[0]}@{c[3]}: rebuilt={got!r} cpython={want!r}")
    raw = float(cm.numpy().reshape(-1)[0])
    if f32bits(raw) != f32bits(want):
      scv += 1
  print(f"selfcheck rows={len(cgroups)}  selfcheck disagreeing={sc}")
  print(f"rows where CPython's DOUBLE-PRECISION value differs from its f32 value: {scv}")
  if sc:
    print("REFUSED: the REBUILD does not reproduce CPython's own value, so it cannot be pointed at the port yet")
    return 3
  # 3. THE PORT'S VALUE, FROM THE PORT'S OWN GRAPH.
  pvbad = 0
  for p, c in zip(pgroups, cgroups):
    t = Tensor(UOp.const(frombits(int(p[3])), dtypes.weakfloat), device="PYTHON")
    want = committed_value(cpython_method(t, p[0], p[1], p[2])._uop)
    got = committed_value(build_port(p[5], p[4]))
    if f32bits(got) != f32bits(want):
      pvbad += 1
      if pvbad <= 8:
        print(f"  VALUE {p[0]}@{p[3]}: port={got!r} cpython={want!r}")
  print(f"value rows compared={len(pgroups)}  value rows differing={pvbad}")
  ok = not bad and not pvbad
  print("VERDICT: PASS" if ok else "VERDICT: FAIL")
  print(f"SUMMARY graph_rows={len(pgroups)} graph_differing={len(bad)} "
        f"value_rows={len(pgroups)} value_differing={pvbad} "
        f"selfcheck_rows={len(cgroups)} selfcheck_disagreeing={sc}")
  return 0 if ok else 1


if __name__ == "__main__":
  sys.exit(main(sys.argv))
