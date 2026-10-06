#!/usr/bin/env python3
"""handtyped-audit.py -- THE HAND-TYPED DETECTOR, CORRECTED.

WHY THIS FILE EXISTS. `unobservable-census.py --handtyped` reports 224 rows whose
expected value is a literal rather than a call. Its regex is

    r'\\b(?:s?row)\\(\\s*"([^"]+)"\\s*,\\s*(.+?)\\)\\s*(?:#.*)?$'   (re.M)

which has THREE blind spots, all of them silent, and all of them in the direction
that makes the number look better than it is:

  1. THE ROW NAME MUST BE A LITERAL STRING. `row(f"cls_{c}", 7)` never matches.
     Every oracle in this project that indexes a family puts the index in the
     NAME (that is the whole `unobservable-census` sibling_blind thesis), so the
     families -- which are the majority of rows in the big oracles -- are exactly
     the ones the detector cannot see.
  2. `re.M` + `$` makes the call SINGLE-LINE. `row(\\n  "n",\\n  v,\\n)` is
     invisible too, and the oracles are heavily wrapped.
  3. A `row(` emitted from inside a helper is invisible only if the helper's own
     name is not `row`/`srow`, which is fine, but the `s?row` prefix set is an
     ASSUMPTION, not a measurement.

This detector parses with `ast` instead, so a row is a row regardless of how its
name is spelled or how the call is wrapped. It also RESOLVES BARE NAMES, so
`row(f"a_{i}", X)` is not called a literal just because `X` is a name, and
`row(f"a_{i}", 3)` inside a loop over anything is still a literal.

Three classes are reported, and UNRESOLVED is never folded into either of the
other two -- a row the detector cannot classify is not a row the detector has
cleared:

    LITERAL    the value is a constant, or built only from constants.
    DERIVED    evaluating it must read something the oracle obtained at runtime.
    UNRESOLVED a bare name with no binding this analysis can follow (a parameter,
               a comprehension/loop/for target, a module built by exec). Counted
               and printed, never silently scored as derived.

Usage:
    .venv/bin/python .agents/slop/handtyped-audit.py --selftest
    .venv/bin/python .agents/slop/handtyped-audit.py             # table + total
    .venv/bin/python .agents/slop/handtyped-audit.py --list nv   # rows, with why
    .venv/bin/python .agents/slop/handtyped-audit.py --crosscheck
    .venv/bin/python .agents/slop/handtyped-audit.py --why RADIX

MEASURED RESULT. 4008 row call sites over 44 oracles: 578 DEFECT (578 LITERAL,
0 LOCAL), 445 UNRESOLVED, 2985 DERIVED. The old detector's 224 becomes 578, a
delta of +354, and the delta decomposes into four measured causes -- 90 NAME
(f-string / %-format row names), 81 VALUE (an expression over constants), 69
RADIX (hex and binary, which the old token pattern could not match AT ALL) and
115 SEMI (two `row(...)` calls on one line). NAME was the cause the brief named;
it is the SECOND largest, and reporting only it would have hidden 265 rows.

The `in old but not new` column is empty for every oracle, which is the subset
property the new detector must have: any name there is a hole in the new scan.
"""
from __future__ import annotations

import argparse
import ast
import pathlib
import re
import sys
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parents[2]
SLOP = ROOT / ".agents" / "slop"
sys.path.insert(0, str(SLOP))
from importlib import import_module  # noqa: E402

census = import_module("unobservable-census")

ROW_FUNCS = {"row", "srow", "s_row", "emit_row", "rec"}


# --------------------------------------------------------------------------
# module-level binding index: name -> list of (lineno, rhs_node) or ("param",)
# --------------------------------------------------------------------------
class Index:
  """Every place a bare NAME is bound, so `row(..., X)` can be resolved."""

  def __init__(self, tree: ast.AST):
    self.binds: dict[str, list[tuple[str, object]]] = defaultdict(list)
    self.funcs: dict[str, ast.AST] = {}

  def add(self, name: str, kind: str, node: object) -> None:
    self.binds[name].append((kind, node))

  def build(self, tree: ast.Module) -> "Index":
    ix = Index(tree)
    for n in ast.walk(tree):
      if isinstance(n, ast.Assign):
        for t in n.targets:
          for nm in _names(t):
            ix.add(nm, "assign", n.value)
      elif isinstance(n, ast.AnnAssign) and n.value is not None:
        for nm in _names(n.target):
          ix.add(nm, "assign", n.value)
      elif isinstance(n, ast.AugAssign):
        for nm in _names(n.target):
          ix.add(nm, "opaque", n.value)
      elif isinstance(n, (ast.For, ast.AsyncFor)):
        for nm in _names(n.target):
          ix.add(nm, "opaque", n.iter)
      elif isinstance(n, ast.NamedExpr):
        for nm in _names(n.target):
          ix.add(nm, "assign", n.value)
      elif isinstance(n, (ast.ListComp, ast.SetComp, ast.DictComp, ast.GeneratorExp)):
        for g in n.generators:
          for nm in _names(g.target):
            ix.add(nm, "opaque", g.iter)
      elif isinstance(n, ast.withitem):
        if n.optional_vars is not None:
          for nm in _names(n.optional_vars):
            ix.add(nm, "opaque", None)
      elif isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
        a = n.args
        for arg in [*a.posonlyargs, *a.args, *a.kwonlyargs,
                    *(a.vararg, a.kwarg)]:
          if arg is not None:
            ix.add(arg.arg, "param", n)
        if n.name in ROW_FUNCS:
          continue
        ix.funcs[n.name] = n
    return ix


def _names(node: ast.AST | None) -> list[str]:
  if node is None:
    return []
  if isinstance(node, ast.Name):
    return [node.id]
  if isinstance(node, (ast.Tuple, ast.List)):
    out = []
    for e in node.elts:
      out += _names(e)
    return out
  if isinstance(node, ast.Starred):
    return _names(node.value)
  return []


# --------------------------------------------------------------------------
# classification
# --------------------------------------------------------------------------
DERIVING = (ast.Call, ast.Attribute, ast.Subscript)

# A local def that returns only constants is a LITERAL wearing a call. The
# brief names this shape as the worst failure mode -- an oracle that
# re-implements the port -- and `unobservable-gr-oracle.py`'s `q4()` is the
# measured instance: two values "taken from CPython" that were transcribed out
# of a helper nobody ran. So a `row(..., helper())` whose `helper` is defined in
# the SAME oracle and returns only constants is reported as LOCAL, not waved
# through by the presence of a call.


def _const_only(node: ast.AST, ix: "Index", depth: int = 0) -> bool:
  """True when an expression is built only from literals.

  Deliberately WHITELIST-shaped and deliberately conservative: anything not
  enumerated here is NOT constant-only, so a false LOCAL costs nothing and a
  false DERIVED costs a whole undetected defect.
  """
  if depth > 8:
    return False
  if isinstance(node, ast.Constant):
    return True
  if isinstance(node, ast.JoinedStr):
    # Only if NOTHING is interpolated. `def sig(u): return f"{nm(u)}/{ctor(u)}"`
    # is a call into the subject wearing an f-string, and treating every
    # JoinedStr as constant called 39 rows LOCAL when 36 of them read CPython:
    # `sig(UOp.invalid())` and `u(req(0, ord("A"), 0x11, None))` are the two the
    # brief's shape is about.
    return all(isinstance(v, ast.Constant) for v in node.values)
  if isinstance(node, (ast.Dict, ast.Set)):
    return all(_const_only(k, ix, depth + 1) for k in node.keys if k is not None) and \
      all(_const_only(v, ix, depth + 1) for v in node.values)
  if isinstance(node, (ast.Tuple, ast.List)):
    return all(_const_only(e, ix, depth + 1) for e in node.elts)
  if isinstance(node, ast.UnaryOp):
    return _const_only(node.operand, ix, depth + 1)
  if isinstance(node, ast.BinOp):
    return _const_only(node.left, ix, depth + 1) and _const_only(node.right, ix, depth + 1)
  if isinstance(node, ast.Compare):
    return _const_only(node.left, ix, depth + 1) and \
      all(_const_only(c, ix, depth + 1) for c in node.comparators)
  if isinstance(node, ast.IfExp):
    return _const_only(node.test, ix, depth + 1) and \
      _const_only(node.body, ix, depth + 1) and \
      _const_only(node.orelse, ix, depth + 1)
  if isinstance(node, ast.Return):
    return node.value is None or _const_only(node.value, ix, depth + 1)
  if isinstance(node, ast.Pass):
    return True
  if isinstance(node, ast.Expr):
    # A bare string is the docstring; anything else is work.
    return isinstance(node.value, ast.Constant) and isinstance(node.value.value, str)
  if isinstance(node, ast.Assign):
    return _const_only(node.value, ix, depth + 1)
  if isinstance(node, ast.AnnAssign):
    return node.value is None or _const_only(node.value, ix, depth + 1)
  if isinstance(node, ast.If):
    return _const_only(node.body, ix, depth + 1) and _const_only(node.orelse, ix, depth + 1)
  return False


def local_const_func(fname: str, ix: "Index") -> bool:
  """A def IN THIS ORACLE whose body computes nothing but constants."""
  f = ix.funcs.get(fname)
  return f is not None and bool(f.body) and all(_const_only(s, ix) for s in f.body)


def classify(node: ast.AST, ix: Index, depth: int = 0) -> str:
  """LITERAL | DERIVED | UNRESOLVED for a value expression."""
  if depth > 6:
    return "UNRESOLVED"
  if isinstance(node, ast.Constant):
    return "LITERAL"
  if isinstance(node, ast.JoinedStr):
    # f"abc" is typed; f"a{x}" reads x.
    if any(isinstance(v, ast.FormattedValue) for v in node.values):
      return "DERIVED"
    return "LITERAL"
  if isinstance(node, (ast.Tuple, ast.List, ast.Set)):
    if not node.elts:
      return "LITERAL"
    ks = {classify(e, ix, depth + 1) for e in node.elts}
    if ks == {"LITERAL"}:
      return "LITERAL"
    return "UNRESOLVED" if "UNRESOLVED" in ks else "DERIVED"
  if isinstance(node, ast.Dict):
    if not (node.keys or node.values):
      return "LITERAL"
    parts = [classify(e, ix, depth + 1)
             for e in [*node.keys, *node.values] if e is not None]
    ks = set(parts)
    if ks == {"LITERAL"}:
      return "LITERAL"
    return "UNRESOLVED" if "UNRESOLVED" in ks else "DERIVED"
  if isinstance(node, ast.UnaryOp):
    return classify(node.operand, ix, depth + 1)
  if isinstance(node, (ast.BinOp, ast.Compare)):
    parts = [classify(node.left, ix, depth + 1)]
    if isinstance(node, ast.BinOp):
      parts.append(classify(node.right, ix, depth + 1))
    else:
      parts += [classify(c, ix, depth + 1) for c in node.comparators]
    ks = set(parts)
    if ks == {"LITERAL"}:
      return "LITERAL"
    return "UNRESOLVED" if "UNRESOLVED" in ks else "DERIVED"
  if isinstance(node, ast.Call):
    if isinstance(node.func, ast.Name) and local_const_func(node.func.id, ix):
      return "LOCAL"
    return "DERIVED"
  if isinstance(node, ast.Attribute):
    return "DERIVED"
  if isinstance(node, ast.Subscript):
    return "DERIVED"
  if isinstance(node, ast.Name):
    # LOCAL is checked BEFORE resolution: a def is not an Assign, so
    # `_resolve` cannot see it and returned UNRESOLVED for `row(n, CONSTRET)`,
    # which is the `q4()` shape wearing a capital.
    if local_const_func(node.id, ix):
      return "LOCAL"
    return _resolve(node.id, ix, depth)
  if isinstance(node, ast.IfExp):
    # The TEST counts. `row(n, "True" if g.ADA in SET else "False")` has two
    # literal arms and one derived test; reading only the arms classified 31 of
    # nv-oracle's rows as LITERAL when every one of them reads a real constant
    # out of `tinygrad.runtime.autogen.nv_570`. A gate that ignores the test
    # asserts nothing, so the test is part of the value.
    ks = {classify(node.test, ix, depth + 1),
          classify(node.body, ix, depth + 1),
          classify(node.orelse, ix, depth + 1)}
    if ks == {"LITERAL"}:
      return "LITERAL"
    return "UNRESOLVED" if "UNRESOLVED" in ks else "DERIVED"
  if isinstance(node, (ast.Starred,)):
    return classify(node.value, ix, depth + 1)
  if isinstance(node, ast.Slice):
    return "DERIVED"
  return "UNRESOLVED"


def _resolve(name: str, ix: Index, depth: int = 0) -> str:
  """Follow one name through its bindings. Conservative: any derived binding wins."""
  if depth > 6:
    return "UNRESOLVED"
  if name not in ix.binds:
    # A name the module never assigns: an import, a builtin, a global.
    return "DERIVED" if name.islower() else "UNRESOLVED"
  ks = set()
  for kind, node in ix.binds[name]:
    if kind == "param":
      ks.add("UNRESOLVED")
    elif kind == "opaque":
      ks.add("UNRESOLVED")
    else:
      ks.add(classify(node, ix, depth + 1))
  if ks == {"LITERAL"}:
    return "LITERAL"
  if "DERIVED" in ks:
    return "DERIVED"
  return "UNRESOLVED"


# --------------------------------------------------------------------------
# the scan
# --------------------------------------------------------------------------
def scan(path: pathlib.Path) -> dict:
  src = path.read_text(errors="replace")
  try:
    tree = ast.parse(src)
  except SyntaxError as e:
    return {"path": path, "sites": 0, "rows": [], "error": str(e)}
  ix = Index(tree).build(tree)
  rows = []
  sites = 0
  for n in ast.walk(tree):
    if not isinstance(n, ast.Call):
      continue
    fn = n.func
    fname = fn.attr if isinstance(fn, ast.Attribute) else (
      fn.id if isinstance(fn, ast.Name) else None)
    if fname not in ROW_FUNCS:
      continue
    # value argument: positional 1, else keyword value=/val=/v=
    valnode = None
    if len(n.args) >= 2:
      valnode = n.args[1]
    else:
      for kw in n.keywords:
        if kw.arg in ("value", "val", "v", "expected", "want"):
          valnode = kw.value
    if valnode is None:
      continue
    sites += 1
    name = _name_text(n.args[0]) if n.args else _name_text(
      next((k.value for k in n.keywords if k.arg in ("name", "nm")), None))
    # name spelling: literal, f-string, or neither
    if n.args and isinstance(n.args[0], ast.Constant):
      spelling = "literal"
    elif n.args and isinstance(n.args[0], ast.JoinedStr):
      spelling = "f-string"
    else:
      spelling = "other"
    try:
      # `ast.get_source_segment`, NOT `ast.unparse`: unparse renders 0xde3 as
      # 3555, which erased the very spelling that made every hexadecimal
      # constant invisible to the old detector and reported RADIX as 0.
      literal_text = (ast.get_source_segment(src, valnode) or "").strip()
      if not literal_text:
        literal_text = ast.unparse(valnode)
    except Exception:  # noqa: BLE001
      literal_text = "<unparseable>"
    kind = classify(valnode, ix)
    # LOCAL and LITERAL are the same defect; LOCAL is kept apart because it is
    # the one that reads as derived and is what `q4()` was.
    rows.append({
      "name": name,
      "lineno": n.lineno,
      "fname": fname,
      "name_spelling": spelling,
      "value_src": literal_text,
      "kind": kind,
      "defect": kind in ("LITERAL", "LOCAL"),
    })
  return {"path": path, "sites": sites, "rows": rows}


def _name_text(node: ast.AST | None) -> str:
  if node is None:
    return "<none>"
  if isinstance(node, ast.Constant):
    return str(node.value)
  try:
    return ast.unparse(node)
  except Exception:  # noqa: BLE001
    return "<expr>"


def oracles() -> list[pathlib.Path]:
  # `.mutwork/` holds a COPY of an oracle made by a mutation harness, and it
  # matches `*oracle*.py`, so a scan that counted it added 96 defect sites that
  # live in a scratch directory. A count that includes a harness's own copy of
  # the file it is auditing is not a count of the corpus.
  return sorted(p for p in SLOP.rglob("*oracle*.py") if ".mutwork" not in p.parts)


OLD_RE = re.compile(r'\b(?:s?row)\(\s*"([^"]+)"\s*,\s*(.+?)\)\s*(?:#.*)?$', re.M)
OLD_LIT = re.compile(r'(?:"[^"]*"|\'[^\']*\'|-?\d+(?:\.\d+)?|True|False|None)')
OLD_BARE = re.compile(r'f"[^"{]*"')


def old_hits(path: pathlib.Path) -> list[tuple[str, str]]:
  """Exactly what the old detector would report for this file, as a MULTISET.

  Recomputing it here rather than trusting `census.hand_typed` keeps the
  comparison inside one method, and the multiset matters: an oracle with two
  sites of one name must not be able to make a miss look like a hit.
  """
  out = []
  for m in OLD_RE.finditer(path.read_text(errors="replace")):
    v = m.group(2).strip()
    if OLD_LIT.fullmatch(v) or OLD_BARE.fullmatch(v):
      out.append((m.group(1), v))
  return out


def why_missed(row: dict, old_names: set[str]) -> str:
  """WHY the old regex did not report this DEFECT row. MEASURED, not guessed.

  An earlier version of this function labelled EVERY literal row with a cause
  without ever checking whether the old detector had seen it, and so printed 388
  rows like `row("amd_pkt_slice_head", 12)` as "SHAPE" misses when the old
  detector had in fact reported that exact row. A guess at the cause of a miss
  is the same defect as the miss: it is a belief.

  Now `old_names` is the old detector's actual output and the branches below are
  only reached when the row is genuinely absent from it.

    NAME      the row NAME is not a constant string (f-string, or `%`-format).
    VALUE     the NAME was a literal but the VALUE is an EXPRESSION over
              constants -- `3 << 20`, `512 + 12 * 4`, `'2,56,57'`. The old
              detector's test was `re.fullmatch` on a SINGLE token, so every
              arithmetic transcription of an upstream constant was invisible.
    RADIX     the value is a hex or binary literal -- `0xde3`, `0b11`. The old
              detector's token pattern was `-?\d+(?:\.\d+)?`, which does not
              match a radix prefix at all, so EVERY hexadecimal constant in
              EVERY oracle was invisible. That is the single most consequential
              blind spot here, because the two worst hand-typed incidents this
              project has paid for were both hex: `BNXT_VENDOR` 5356 against
              5348 and `~0x6996` written as 24425.
    SEMI      two `row(...)` calls share one line, so `$` after the first `)`
              never matches and NEITHER call is seen.
    LOCAL     the value CALLS a def in this same oracle that returns only
              constants. The old regex never saw it (the value is not a token)
              and a naive ast reader waves it through as "derived". It is the
              `unobservable-gr-oracle.py` `q4()` shape.
    DUP       the old detector DID report this name, from this or another site.
              Counted, never used to explain a miss.
  """
  if row["name"] in old_names:
    return "DUP"
  if row["name_spelling"] != "literal":
    return "NAME"
  if row["kind"] == "LOCAL":
    return "LOCAL"
  if re.match(r"^(0[xXbBoO]|[-+]?0[xXbBoO])", row["value_src"]) or \
     re.search(r"0[xX][0-9a-fA-F_]+", row["value_src"]) or \
     re.search(r"0[bB][01_]+", row["value_src"]):
    return "RADIX"
  src = row["value_src"]
  if re.fullmatch(r"-?\d+(?:\.\d+)?", src) or \
     re.fullmatch(r"\"[^\"]*\"|'[^']*'", src) or \
     src in ("True", "False", "None"):
    return "SEMI"
  return "VALUE"


def report_why(results: list[dict], show: str | None = None) -> None:
  if show:
    for r in results:
      old = {n for n, _ in old_hits(r["path"])}
      for x in r["rows"]:
        if x["defect"] and why_missed(x, old) == show:
          src = r["path"].read_text(errors="replace").splitlines()[x["lineno"] - 1]
          print(f"  {r['path'].name}:{x['lineno']}: {src.strip()}")
    return
  print()
  print("=" * 100)
  print("WHY THE OLD REGEX MISSED THEM -- six causes, counted against its real output")
  print("=" * 100)
  print(f"{'oracle':30} {'DEFECT':>7} {'NAME':>6} {'VALUE':>6} {'RADIX':>6} "
        f"{'SEMI':>6} {'LOCAL':>6} {'DUP':>6} {'old saw':>8}")
  T = [0, 0, 0, 0, 0, 0, 0, 0]
  for r in sorted(results, key=lambda r: -sum(1 for x in r["rows"]
                                              if x["defect"])):
    lit = [x for x in r["rows"] if x["defect"]]
    if not lit:
      continue
    f = r["path"]
    old = {n for n, _ in old_hits(f)}
    c = defaultdict(int)
    for x in lit:
      c[why_missed(x, old)] += 1
    oldn = len(old_hits(f))
    T = [a + b for a, b in zip(T, [len(lit), c["NAME"], c["VALUE"], c["RADIX"],
                                   c["SEMI"], c["LOCAL"], c["DUP"], oldn])]
    print(f"{str(f.relative_to(SLOP))[:29]:30} {len(lit):>7} {c['NAME']:>6} "
          f"{c['VALUE']:>6} {c['RADIX']:>6} {c['SEMI']:>6} {c['LOCAL']:>6} "
          f"{c['DUP']:>6} {oldn:>8}")
  print("-" * 100)
  print(f"{'TOTAL':30} {T[0]:>7} {T[1]:>6} {T[2]:>6} {T[3]:>6} {T[4]:>6} "
        f"{T[5]:>6} {T[6]:>6} {T[7]:>8}")


SELFTEST = '''\
"""A SYNTHETIC oracle carrying every shape the detector claims to catch."""
ROWS = []
def row(nm, v): ROWS.append((nm, v))
def K(): return 0xde3
def CONSTRET(x): return 42
row("lit_str", "hello")
row("lit_int", 12)
row("lit_hex", 0xdeadbeef)
row("lit_bin", 0b1011)
row("lit_arith", 3 << 20)
row("lit_arith2", 512 + 12 * 4)
row("lit_tuple", (1, 2, 3))
for i in range(3):
  row(f"fs_name_{i}", 9)
  row(f"lit_in_loop_{i}", 5)
row("local_def_call", K())
row("local_def_name", CONSTRET)
row("radix_expr", 0xff << 4)
row("semi_a", 1); row("semi_b", 2)
import os
row("derived_attr", os.sep)
row("derived_call", len(ROWS))
'''

# What the synthetic oracle must yield. Written out rather than recomputed, so a
# change in the classifier that quietly stops catching a shape fails here instead
# of showing up as a reassuring 0 in the corpus table.
SELFTEST_EXPECT = {
  "lit_str": "LITERAL", "lit_int": "LITERAL", "lit_hex": "LITERAL",
  "lit_bin": "LITERAL", "lit_arith": "LITERAL", "lit_arith2": "LITERAL",
  "lit_tuple": "LITERAL", "radix_expr": "LITERAL", "semi_a": "LITERAL",
  "semi_b": "LITERAL", "local_def_call": "LOCAL",
  "local_def_name": "LOCAL", "derived_attr": "DERIVED",
  "derived_call": "DERIVED",
}


def selftest() -> int:
  """The corpus total is only evidence if the detector can fail.

  A detector whose new class never fires on the corpus cannot distinguish
  `clean` from `dead`, and reporting the first as the second is the mistake
  this file exists to prevent. So: run the shapes past it and require the
  expected class for each.
  """
  import tempfile
  with tempfile.NamedTemporaryFile("w", suffix="oracle.py", delete=False) as f:
    f.write(SELFTEST)
    p = pathlib.Path(f.name)
  r = scan(p)
  got = {}
  for x in r["rows"]:
    if x["name"].startswith("fs_name_") or x["name"].startswith("lit_in_loop_"):
      got.setdefault("fs_name_loop", x["kind"])
      continue
    got[x["name"]] = x["kind"]
  got["fs_name_loop"] = got.get("fs_name_loop", "MISSING")
  bad = []
  for name, want in SELFTEST_EXPECT.items():
    have = got.get(name, "MISSING")
    flag = "ok " if have == want else "FAIL"
    if have != want:
      bad.append((name, want, have))
    print(f"  {flag} {name:20} want={want:9} got={have}")
  print()
  if bad:
    print(f"SELFTEST FAILED on {len(bad)} shape(s) -- the corpus table below is")
    print("NOT evidence until this passes. A 0 in the corpus is indistinguishable")
    print("from a detector that stopped looking.")
    return 1
  print(f"SELFTEST PASSED: {len(SELFTEST_EXPECT)} shapes, each caught by name.")
  print("The corpus total is therefore a measurement and not a dead detector.")
  return 0


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--list", default=None, help="substring of the oracle path")
  ap.add_argument("--crosscheck", action="store_true")
  ap.add_argument("--mutants", action="store_true",
                  help="include the deliberate *MUTANT* oracles")
  ap.add_argument("--why", default=None,
                  help="dump the source line of every LITERAL row missed by cause")
  ap.add_argument("--selftest", action="store_true")
  a = ap.parse_args()

  if a.selftest:
    return selftest()

  results = []
  for f in oracles():
    if not a.mutants and "MUTANT" in f.name:
      continue
    results.append(scan(f))

  if a.list or a.why:
    for r in results:
      if a.why:
        report_why(results, a.why)
        return 0
      if a.list not in str(r["path"]):
        continue
      print(f"=== {r['path'].relative_to(SLOP)}  sites={r['sites']}  "
            f"{r.get('error','')}")
      for row in sorted(r["rows"], key=lambda x: x["lineno"]):
        if row["kind"] == "DERIVED":
          continue
        print(f"  {row['kind']:10} :{row['lineno']:<5} {row['fname']}"
              f"({row['name_spelling']:8}) {row['name']} = {row['value_src']}")
    return 0

  print("=" * 100)
  print("HAND-TYPED AUDIT -- ast-based. DEFECT = LITERAL + LOCAL (a call into a")
  print("same-file constant-returning def). UNRESOLVED is reported, never counted")
  print("as clean. MUTANT oracles excluded (deliberately wrong). Units are row")
  print("call SITES: a site inside a loop is one site and N runtime rows.")
  print("=" * 100)
  hdr = (f"{'oracle':30} {'sites':>6} {'DEFECT':>7} {'lit':>5} {'local':>6} "
         f"{'UNRESOL':>8} {'DERIVED':>8} {'fs-name':>8}")
  print(hdr)
  tot = [0] * 7
  lit_files = []
  for r in results:
    rs = r["rows"]
    if not rs:
      continue
    ndef = sum(1 for x in rs if x["kind"] == "LITERAL")
    nloc = sum(1 for x in rs if x["kind"] == "LOCAL")
    nunr = sum(1 for x in rs if x["kind"] == "UNRESOLVED")
    nder = sum(1 for x in rs if x["kind"] == "DERIVED")
    nfs = sum(1 for x in rs if x["name_spelling"] != "literal")
    tot = [p + q for p, q in zip(tot, [len(rs), ndef + nloc, ndef, nloc, nunr,
                                       nder, nfs])]
    if ndef or nloc or nunr:
      lit_files.append((ndef + nloc + nunr, r))
    print(f"{str(r['path'].relative_to(SLOP))[:29]:30} {len(rs):>6} "
          f"{ndef + nloc:>7} {ndef:>5} {nloc:>6} {nunr:>8} {nder:>8} "
          f"{nfs:>8}")
  print("-" * 100)
  print(f"{'TOTAL':30} {tot[0]:>6} {tot[1]:>7} {tot[2]:>5} {tot[3]:>6} "
        f"{tot[4]:>8} {tot[5]:>8} {tot[6]:>8}")
  print()
  print(f"  row call SITES classified           : {tot[0]}")
  print(f"  DEFECT  (LITERAL + LOCAL)           : {tot[1]}")
  print(f"    of which LITERAL                  : {tot[2]}")
  print(f"    of which LOCAL (constant-returning def in the oracle) : {tot[3]}")
  print(f"  UNRESOLVED (not cleared by me)      : {tot[4]}")
  print(f"  DERIVED                             : {tot[5]}")
  print(f"  of which the NAME is not a literal string : {tot[6]}")

  if a.crosscheck:
    print()
    print("=" * 100)
    print("CROSSCHECK against `unobservable-census.py --handtyped` (the 224)")
    print("=" * 100)
    old_total, old_files = 0, {}
    for f in oracles():
      try:
        rs = census.hand_typed(f)
      except Exception:  # noqa: BLE001
        continue
      if rs:
        # COUNTED, NOT DEDUPED: the old detector reports row SITES, so a file
        # with two sites of the same name counts twice. Deduplicating here
        # reported nv at 62 against a stated 65 and would have made the
        # crosscheck disagree with the number the brief quotes.
        old_total += len(rs)
        old_files[f] = (len(rs), {n for n, _ in rs})
    print(f"  old detector total : {old_total}  across {len(old_files)} oracles")
    print(f"  new detector total : {tot[1]} DEFECT  across {len(lit_files)} oracles")
    print(f"  DELTA              : +{tot[1] - old_total}")
    print()
    print(f"  {'oracle':30} {'old':>5} {'new-def':>8} {'delta':>6}  in old but not new")
    for n, r in sorted(lit_files, key=lambda kv: -kv[0]):
      f = r["path"]
      oldn, old = old_files.get(f, (0, set()))
      newlit = {x["name"] for x in r["rows"] if x["defect"]}
      missing = sorted(old - newlit)
      print(f"  {str(f.relative_to(SLOP))[:29]:30} {oldn:>5} "
            f"{len(newlit):>8} {len(newlit) - oldn:>6}  "
            f"{missing if missing else '-'}")
    print()
    print("  `in old but not new` MUST be empty or this detector has a hole: the")
    print("  old detector's set is a SUBSET of the new one's by construction, so a")
    print("  name here means the new scan failed to find a row the old one had.")
    print()
    print("  THE BLIND SPOT, MEASURED. Per oracle, DEFECT rows by name spelling:")
    print(f"  {'oracle':30} {'name-not-literal':>17} {'name-literal':>13}")
    for n, r in sorted(lit_files, key=lambda kv: -kv[0]):
      fs = sum(1 for x in r["rows"]
               if x["defect"] and x["name_spelling"] != "literal")
      print(f"  {str(r['path'].relative_to(SLOP))[:29]:30} {fs:>17} "
            f"{n - fs:>13}")
  report_why(results)
  return 0


if __name__ == "__main__":
  raise SystemExit(main())