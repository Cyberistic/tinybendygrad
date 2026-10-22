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

DT = {"weakint": dtypes.weakint, "bool": dtypes.bool, "i32": dtypes.int32,
      "u32": dtypes.uint32, "i64": dtypes.int64, "u64": dtypes.uint64,
      "f32": dtypes.float32, "weakfloat": dtypes.weakfloat}


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

def parse(p, ar):
  """One node.  A leaf is a CONST or a PARAM; a head is an op with an OPTIONAL
  dtype suffix, and the dtype is the node's ARG -- the port's own spelling."""
  tk = p.take()
  if tk.kind == "(":
    head = p.take()
    name = head.text.lower()
    dt = None
    if p.peek() is not None and p.peek().kind == ":":
      p.take()
      dt = DT[p.take().text]
    srcs = []
    while p.peek() is not None and p.peek().kind != ")":
      srcs.append(parse(p, ar))
    p.take()  # the )
    op = Ops[name.upper()]
    if dt is not None:
      return UOp(op, tuple(srcs), dt)
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
  return UOp.variable(w, 0, 100, vdt(w))

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
    u = parse(P(lex(expr)), None)
    ans[name] = sh(sym.rewrite(u))
  return ans

def port_answers(path):
  """THE PORT'S OWN DRIVER'S OUTPUT, one line per case IN THE CASE FILE'S ORDER.
  The driver prints `root=... sym=<s-expr> rm=<s-expr>` and no name, so the rows
  are matched BY POSITION -- which is why the case file and the output have to be
  produced in one go."""
  ans = []
  for ln in open(path):
    parts = dict(p.split("=", 1) for p in ln.split(" ") if "=" in p)
    if "sym=" in parts:
      ans.append(parts["sym"])
  return ans

def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--cases", default=CASES)
  ap.add_argument("--compare", help="the port's driver output to diff against")
  args = ap.parse_args()
  cases = read_cases(args.cases)
  up = upstream(cases)
  if args.compare is None:
    for name, _ in cases:
      print("%s=%s" % (name, up[name]))
    return 0
  port = port_answers(args.compare)
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
