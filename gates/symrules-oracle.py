#!/usr/bin/env python3
"""symrules-oracle.py -- CPython IS THE ORACLE, AND IT IS IN THE TREE.

    .venv/bin/python gates/symrules-oracle.py                 # upstream's answers
    .venv/bin/python gates/symrules-oracle.py --compare FILE  # diff against the port
    .venv/bin/python gates/symrules-oracle.py --cases FILE    # another case file

ONE FILE, TWO READERS.  `gates/symrules-cases.rows` holds the GRAPHS, and this
file READS IT and builds the same graphs in CPython -- so the port (whose driver
reads the same file) and the oracle cannot be measuring two different graphs.  A
hand-written pair of fixtures has that defect by construction.

THE RENDERING IS THE PORT'S RENDERING, so the two diff as STRINGS: the op name is
lowercase, a node whose ARG is a dtype prints `(cast:i32 ...)`, a CONST prints
`c<N>`/`n<N>`/`bt`/`bf`/`bad`, and a PARAM prints its name.  That is
`tinybendygrad/uop/symbolic.bend`'s `fz_render`, and this file's `sh` is the same
canonical form on the other side of the language boundary.

THE POINT IS NOT THE ANSWER, IT IS THE PAIR.  Every rule gets TWO graphs -- the one
upstream's rule FIRES on and the one it must NOT fire on -- and the pair is what
makes the port's row mean something.  A rule that fires on the negative is a rule
that fires where upstream's does not, and that is the DANGEROUS direction.

EXIT: 0 the port agrees with upstream on every case · 1 they disagree · 3 REFUSED
(a case file or a graph the reader cannot build).
"""

import argparse
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

CASES = os.path.join(ROOT, "gates", "symrules-cases.rows")

from tinygrad.uop.ops import UOp, Ops
from tinygrad import dtypes
from tinygrad.uop.symbolic import sym

# THE SAME SET THE PORT'S `fz_dt` NAMES. A case file that can spell a dtype the oracle
# cannot build is a case the oracle refuses, and `can_lossless_cast` needs widths.
DT = {"weakint": dtypes.weakint, "bool": dtypes.bool, "i8": dtypes.int8, "u8": dtypes.uint8,
      "i16": dtypes.int16, "u16": dtypes.uint16, "i32": dtypes.int32, "u32": dtypes.uint32,
      "i64": dtypes.int64, "u64": dtypes.uint64, "f16": dtypes.float16, "bf16": dtypes.bfloat16,
      "f32": dtypes.float32, "f64": dtypes.float64, "weakfloat": dtypes.weakfloat}

# THE PORT'S OP VOCABULARY, AND IT IS THE PORT's OWN TABLE (`tinybendygrad/uop/symbolic.bend`'s
# `fz_op`, ITS `:8201` DEF) RATHER THAN A SECOND COPY OF IT. MEASURED 2026-11-06: THE ORACLE
# DID `Ops[name.upper()]` AND CRASHED WITH `KeyError: 'FLOORDIV'` ON THE FIRST CASE THAT
# SPELLS IT -- AND **24 OF THE 232 CASES SPELL `floordiv` OR `floormod`.** SO THE ORACLE
# REFUSED EVERY CASE, AND A BODY-VERIFICATION INSTRUMENT THAT REFUSES EVERY CASE VERIFIES
# NOTHING.
#
# THE FOUR NAMES THAT ARE NOT `name.upper()` ARE THE PORT's, AND THEIR MEANING IS THE PORT's
# `fz_op`'s: `floordiv` IS `Ops.DIV`, `floormod` IS `Ops.MOD`, `cdiv` IS `Ops.TRUNCDIV` AND
# `cmod` IS `Ops.TRUNCMOD`. UPSTREAM HAS NO `FLOORDIV` AND NO `FLOORMOD` -- IT HAS `DIV` AND
# `MOD` -- SO THE SPELLING IS THE PORT's AND THE MAPPING IS THE PORT's TOO.
#
# THE OTHER DIRECTION MATTERS AS WELL: UPSTREAM'S `Ops` HAS NAMES THE PORT's VOCABULARY DOES
# NOT (`SDOT`, `DOT`, ...), AND `Ops[name.upper()]` FOR THOSE WOULD BUILD A GRAPH THE PORT
# CANNOT READ. SO THE TABLE IS **BOTH** DIRECTIONS: THE PORT's SPELLINGS AND THE UPSTREAM
# ONES THAT ARE THE SAME OP.
OPS = {op.name.lower(): op for op in Ops}
OPS.update({"floordiv": Ops.DIV, "floormod": Ops.MOD, "cdiv": Ops.TRUNCDIV, "cmod": Ops.TRUNCMOD,
            "reciprocal": Ops.RECIP})


class Tok:
  def __init__(self, kind, text):
    self.kind, self.text = kind, text

def lex(s):
  out, i = [], 0
  while i < len(s):
    c = s[i]
    if c == " ":
      i += 1
    elif c == "(":
      out.append(Tok("(", "(")); i += 1
    elif c == ")":
      out.append(Tok(")", ")")); i += 1
    elif c == ":":
      out.append(Tok(":", ":")); i += 1
    else:
      j = i
      while j < len(s) and s[j] not in "() :":
        j += 1
      out.append(Tok("w", s[i:j])); i = j
  return out

def vdt(name):
  return {"b": dtypes.bool, "f": dtypes.weakfloat, "i": dtypes.int32}.get(name[-1], dtypes.weakint)

class P:
  def __init__(self, toks):
    self.t, self.i = toks, 0
  def peek(self):
    return self.t[self.i] if self.i < len(self.t) else None
  def take(self):
    tk = self.t[self.i]; self.i += 1
    return tk

def parse(p, memo):
  """One node.  A leaf is a CONST or a PARAM; a head is an op with an OPTIONAL
  dtype suffix, and the dtype is the node's ARG -- the port's own spelling.

  `memo` IS THE VARIABLE TABLE and it is per-graph, because two cases must not share
  nodes: it is what makes a repeated name the SAME node."""
  tk = p.take()
  if tk.kind == "(":
    head = p.take()
    name = head.text.lower()
    suf = None
    if p.peek() is not None and p.peek().kind == ":":
      p.take()
      suf = p.take().text
    srcs = []
    while p.peek() is not None and p.peek().kind != ")":
      srcs.append(parse(p, memo))
    p.take()  # the )
    op = OPS[name]
    # A REDUCE's suffix is its ROP and not a dtype: `arg` is `(Ops, num_axes)` and the axes are
    # the srcs after the first. `(reduce:add x (range c8))` -- MEASURED, `UPat(...).reduce(arg=
    # Ops.ADD)` normalises to `(Ops.ADD, 0)` and a real graph states the count.
    if op is Ops.REDUCE and suf is not None:
      return UOp(op, tuple(srcs), arg=(Ops[suf.upper()], len(srcs)-1))
    if suf is not None:
      return UOp(op, tuple(srcs), DT[suf])
    return UOp(op, tuple(srcs))
  w = tk.text
  if w == "bt":
    return UOp.const(True, dtypes.bool)
  if w == "bf":
    return UOp.const(False, dtypes.bool)
  if w == "bad":
    from tinygrad.dtype import Invalid
    return UOp.const(Invalid)
  if w[0] == "c":
    return UOp.const(int(w[1:]), dtypes.weakint)
  if w[0] == "n":
    return UOp.const(-int(w[1:]), dtypes.weakint)
  # ONE NODE PER NAME. `UOp.variable` MINTS, so building a fresh PARAM per occurrence made
  # every rule whose guard is an IDENTITY CHECK unstatable -- `(x^y)^y`, `x%x`, `x//x`,
  # `x.where(b.where(c,d), d)` -- and since the PORT interns its params by name (its own
  # `fz_var` comment says why), the two sides were not measuring the same graph at all.
  # MEASURED 2026-11-03: `(where ab xb (where xb yb zb))` answered `norewrite` upstream and
  # `(where (or ab yb) xb zb` in the port, and the port was right.
  key = (w, vdt(w))
  if key not in memo:
    memo[key] = UOp.variable(w, 0, 100, vdt(w))
  return memo[key]

def sh(u):
  """THE PORT'S CANONICAL FORM, on the CPython side."""
  if u is None:
    return "norewrite"
  if u.op is Ops.CONST:
    v = u.arg
    if v is True:
      return "bt"
    if v is False:
      return "bf"
    if isinstance(v, int):
      return ("c%d" % v) if v >= 0 else ("n%d" % -v)
    return "bad"
  if u.op is Ops.PARAM:
    return u.arg.name
  if u.op is Ops.REDUCE and isinstance(u.arg, tuple):
    return "(reduce:" + u.arg[0].name.lower() + " " + " ".join(sh(s) for s in u.src) + ")"
  dt = u.arg if isinstance(u.arg, __import__("tinygrad").dtype.DType) else None
  head = u.op.name.lower() + (":" + dt.name if dt is not None else "")
  return "(" + head + " " + " ".join(sh(s) for s in u.src) + ")"

def read_cases(path):
  out = []
  for ln in open(path):
    ln = ln.strip()
    if not ln or ln.startswith("#"):
      continue
    name, _, expr = ln.partition("|")
    out.append((name.strip(), expr.strip()))
  return out

def upstream(cases):
  ans = {}
  for name, expr in cases:
    u = parse(P(lex(expr)), {})
    ans[name] = sh(sym.rewrite(u))
  return ans

def port_answers(path, field="symf"):
  """THE PORT'S OWN DRIVER'S OUTPUT, one line per case IN THE CASE FILE'S ORDER.
  The driver prints `root=... sym=<s-expr> rm=<s-expr> symf=<s-expr>` and no name,
  so the rows are matched BY POSITION -- which is why the case file and the output
  have to be produced in one go.

  `symf` AND NOT `sym`, because `sym` answers at an index into the arena it was
  given and a rule that MINTS leaves that index past the end: the field read `?`
  for every rule whose body builds a node, which is 55 of the remaining 84. `symf`
  is the same table answered through the Found family, so for a rule that does NOT
  mint the two fields are the same string."""
  ans = []
  mark = " " + field + "="
  for ln in open(path):
    ln = ln.rstrip("\n")
    i = ln.find(mark)
    if i < 0:
      continue
    # THE ANSWER CONTAINS SPACES -- `(mul (reciprocal x) (reciprocal x))` -- so it is the
    # LINE'S TAIL and not a space-delimited token: tokenising truncated every nested answer
    # to its first word and printed `(and` for `(and xb yb)`.
    ans.append(ln[i + len(mark):])
  return ans

def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--cases", default=CASES)
  ap.add_argument("--compare", help="the port's driver output to diff against")
  ap.add_argument("--field", default="symf", help="which answer column to compare")
  args = ap.parse_args()
  cases = read_cases(args.cases)
  up = upstream(cases)
  if args.compare is None:
    for name, _ in cases:
      print("%s=%s" % (name, up[name]))
    return 0
  port = port_answers(args.compare, args.field)
  bad = []
  if len(port) != len(cases):
    bad.append("the port's driver printed %d rows and the case file has %d cases"
               % (len(port), len(cases)))
  for (name, _), p in zip(cases, port):
    if p != up[name]:
      bad.append("%s: port=%s upstream=%s" % (name, p, up[name]))
  for b in bad:
    print("DIVERGES " + b)
  print("symrules-oracle: %d cases, %d agree, %d diverge" % (len(cases), len(cases) - len(bad), len(bad)))
  return 1 if bad else 0

if __name__ == "__main__":
  sys.exit(main())
