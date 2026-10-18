#!/usr/bin/env python3
"""census.py -- THE WHOLE TREE, not the port subtree.

`gates/paramarg-shape-gate.py`'s `census()` walks `PORT_ROOT` only, so it reads
`94 sites in 30 files` on a tree whose two DRIVERS still build the pre-72f98ffe0
record. `gates/paramarg_shape.bend` and `.agents/slop/graphcmp.bend` are outside
`tinybendygrad/`, so the instrument that names the migration's size cannot see
the two files the migration has not reached.

Two populations, both declared by DISCOVERY (`os.walk` + suffix, doctrine 1):

  ARITY -- every `ParamArg{...}` split on top-level commas, comment-stripped,
    reported per arity. The record is 12 fields; upstream is 13.
  SRC -- every `UOp.new(... OpsBUFFER{}|OpsALLOC{}|OpsPARAM{} ...)` and whether
    its src argument is `param_src(...)`. Upstream gives all three at least
    `src=(shape_to_shape_arg(...),)` (ops.py:829 ALLOC 1187 PARAM 1222, and
    `src=(UOp(Ops.STACK),)` for variable/range_var at 1003).

usage: .venv/bin/python .agents/slop/sizetosrc/census.py [--roots R ...]
"""
from __future__ import annotations
import argparse, os, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
DEFAULT_ROOTS = ("tinybendygrad", "gates", ".agents/slop", "checks", "examples", "probe")
SKIP = frozenset({".git", ".venv", "references", "node_modules", "__pycache__", "artifacts"})
PAIRS = {"(": ")", "[": "]", "{": "}", "<": ">"}


def tracked() -> set[str]:
  """`git ls-tree -r HEAD` -- the files git OWNS. Not `git ls-files`: that is the INDEX,
  and `jj` colocation arms it (`gates/allcopies-census.py`'s R1, MEASURED), so an armed
  index reports the working copy as staged and the intersection silently stops dropping
  anything. The intersection is what removes `*-mut.bend`: MEASURED, `dtype-mut.bend`,
  `realize-mut.bend` and `.linearizer-mut.bend` are NOT in HEAD -- they are scratch that
  `gates/*-mutate.py` writes beside the file it mutates (`MUT_PORT =
  PORT.with_name("dtype-mut.bend")`) -- and they mirror their sibling's site count because
  a harness COPIES the file, not because a generator emits it."""
  import subprocess
  out = subprocess.run(["git", "ls-tree", "-r", "--name-only", "HEAD"],
                       cwd=ROOT, capture_output=True, text=True, check=True).stdout
  return {ln for ln in out.split("\n") if ln}


def split_top(body: str) -> list[str]:
  out, cur, stack = [], [], []
  for ch in body:
    if ch in PAIRS: stack.append(PAIRS[ch])
    elif ch in ")]}>" and stack and ch == stack[-1]: stack.pop()
    if ch == "," and not stack:
      out.append("".join(cur)); cur = []
    else: cur.append(ch)
  out.append("".join(cur))
  return [f.strip() for f in out if f.strip()]


def span(s: str, open_at: int) -> tuple[int, str]:
  """(end, body) for a `{`-opened construct; `open_at` indexes the `{`."""
  i, depth = open_at, 0
  while i < len(s):
    if s[i] == "{": depth += 1
    elif s[i] == "}":
      depth -= 1
      if depth == 0: return i, s[open_at + 1:i]
    i += 1
  return len(s), s[open_at + 1:]


def files(roots, owned: set[str] | None = None):
  for r in roots:
    base = ROOT / r
    if base.is_file():
      yield base; continue
    for dp, dn, fn in os.walk(base):
      dn[:] = sorted(d for d in dn if d not in SKIP)
      for f in sorted(fn):
        if f.endswith(".bend"):
          p = pathlib.Path(dp) / f
          if owned is None or str(p.relative_to(ROOT)) in owned: yield p


def arity_sites(roots, owned=None):
  per: dict[int, dict[str, list[int]]] = {}
  for p in files(roots, owned):
    s = p.read_text()
    for m in re.finditer(r"ParamArg\{", s):
      end, body = span(s, m.end() - 1)
      n = len(split_top(re.sub(r"#[^\n]*", "", body)))
      ln = s[:m.start()].count("\n") + 1
      per.setdefault(n, {}).setdefault(str(p.relative_to(ROOT)), []).append(ln)
  return per


NODE = re.compile(r"UOp\.new\(([^;]*?)Ops(BUFFER|ALLOC|PARAM)\{\}")


def src_sites(roots, owned=None):
  """The src ARGUMENT of every BUFFER/ALLOC/PARAM node construction, found by BALANCED
  scanning (`thread_src.py`'s `calls`/`split_top`, imported rather than re-derived -- two
  copies of a split rule is a second contract with no generator).

  The three classes this reports, which are the three spellings the migration leaves:
    `UOp.new.param(...)`      migrated and correct -- the size node is interned into the
                              arena the node is interned into.
    `UOp.new(ar, K, param_src(ar, n), ...)`  SELF-LOOP. `param_src` drops the arena its
                              size node went into, so the index names nothing in the
                              caller's arena and the node ends up its own `src[0]`.
                              MEASURED: `mxw_buf` -> `src0_op=BUFFER size=N`.
    `UOp.new(ar, K, Nil{}, ...)` no size node at all.
  """
  sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
  import thread_src as ts
  rows = []
  for p in files(roots, owned):
    s = p.read_text()
    # `UOp.new.param(` is a DIFFERENT call shape and `calls()`'s `\bUOp\.new\(` cannot see
    # it (it requires `(` straight after `new`). Both are BUFFER/ALLOC/PARAM node sites,
    # so both are counted here rather than leaving the migrated ones invisible.
    for start, end, args in ts.calls(s, p):
      if len(args) != 5 or not ts.KIND.match(args[1]):
        continue
      arena, op, src, arg, tag = (a.strip() for a in args)
      if ts.PARAMSRC.match(src):
        cls = "param_src-SELF-LOOP"
      elif src == "Nil{}":
        cls = "Nil{}-NO-SIZE"
      else:
        cls = "explicit-src:" + src[:36]
      rows.append((str(p.relative_to(ROOT)), s[:start].count("\n") + 1,
                   ts.KIND.match(op).group(1), cls, arg[:70]))
    for start, end, args in ts.calls(s, p, r"\bUOp\.new\.param\("):
      if len(args) == 5 and ts.KIND.match(args[1]):
        rows.append((str(p.relative_to(ROOT)), s[:start].count("\n") + 1,
                     ts.KIND.match(args[1]).group(1), "new.param-MIGRATED", args[2][:40]))
  return rows


if __name__ == "__main__":
  ap = argparse.ArgumentParser()
  ap.add_argument("--roots", nargs="*", default=list(DEFAULT_ROOTS))
  ap.add_argument("--all", action="store_true", help="include untracked `*-mut.bend` scratch")
  ap.add_argument("--all-sites", action="store_true", help="print every node site")
  a = ap.parse_args()
  owned = None if a.all else tracked()
  if a.all: print("# INCLUDING untracked *-mut.bend scratch (not a migration denominator)")
  per = arity_sites(a.roots, owned)
  print("=== ParamArg arity census (whole tree, git-tracked files only) ===")
  for n in sorted(per):
    tot = sum(len(v) for v in per[n].values())
    print(f"arity={n}: sites={tot} files={len(per[n])}")
    for f, lns in sorted(per[n].items(), key=lambda kv: -len(kv[1])):
      print(f"  {len(lns):3d} {f}  lines={','.join(map(str, lns[:14]))}{'...' if len(lns) > 14 else ''}")
  rows = src_sites(a.roots, owned)
  from collections import Counter
  by = Counter(r[3] for r in rows)
  print(f"\n=== BUFFER/ALLOC/PARAM node constructions: total={len(rows)} ===")
  for cls, n in by.most_common():
    files_n = len({r[0] for r in rows if r[3] == cls})
    print(f"  {cls}: {n} sites in {files_n} files")
  if a.all_sites:
    for f, ln, op, cls, arg in rows:
      print(f"  {f}:{ln} {op} [{cls}] arg={arg}")
