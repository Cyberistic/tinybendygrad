#!/usr/bin/env python3
"""census.py -- the WHOLE TREE, not the port subtree.

`gates/paramarg-shape-gate.py`'s `census()` walks `PORT_ROOT` only, so it reports
`94 sites in 30 files` on a tree whose two DRIVERS were still on the pre-72f98ffe0
record and would not compile. `gates/paramarg_shape.bend` and
`.agents/slop/graphcmp.bend` are outside `tinybendygrad/`, so the instrument that
names the migration's size could not see the two files the migration had not reached.

Two populations, both declared by DISCOVERY (`os.walk` + suffix, AGENTS.md doctrine 1):

  ARITY -- every `ParamArg{...}` split on top-level commas, comment-stripped, reported
    per arity. The migrated record is 12 fields; the pre-72f98ffe0 record was 13.
  SRC   -- every `UOp.new(` / `UOp.new.param(` that builds a BUFFER/ALLOC/PARAM, and
    which of the three spellings it uses. The splitter is `thread_src.py`'s, IMPORTED
    rather than re-derived: two copies of a split rule is a second contract with no
    generator.

`git ls-tree -r HEAD`, NOT `git ls-files`. The index is armed (`jj` colocation, and
MEASURED at 8733 entries against HEAD's 7629 here), so `git ls-files` reports the
working copy as staged and the intersection silently stops dropping anything. The
intersection is what removes `*-mut.bend`: MEASURED, `dtype-mut.bend`, `realize-mut.bend`
and `.linearizer-mut.bend` are NOT in HEAD. They are scratch that `gates/*-mutate.py`
writes beside the file it mutates (`MUT_PORT = PORT.with_name("dtype-mut.bend")`), and
they mirror their sibling's site count because a harness COPIES the file, not because a
generator emits it. `--all` includes them; they are not a migration denominator.

usage: .venv/bin/python .agents/slop/sizetosrc/census.py [--roots R ...] [--all] [--all-sites]
"""
from __future__ import annotations

import argparse
import os
import pathlib
import re
import subprocess
import sys
from collections import Counter

ROOT = pathlib.Path(__file__).resolve().parents[3]
HERE = pathlib.Path(__file__).resolve().parent
DEFAULT_ROOTS = ("tinybendygrad", "gates", ".agents/slop", "checks", "examples", "probe")
SKIP = frozenset({".git", ".venv", "references", "node_modules", "__pycache__", "artifacts"})
PAIRS = {"(": ")", "[": "]", "{": "}", "<": ">"}

sys.path.insert(0, str(HERE))
import thread_src as ts  # noqa: E402


def tracked() -> set[str]:
  """`git ls-tree -r HEAD` -- the files git OWNS."""
  out = subprocess.run(["git", "ls-tree", "-r", "--name-only", "HEAD"],
                       cwd=ROOT, capture_output=True, text=True, check=True).stdout
  return {ln for ln in out.split("\n") if ln}


def files(roots, owned: set[str] | None):
  for r in roots:
    base = ROOT / r
    if base.is_file():
      yield base
      continue
    for dp, dn, fn in os.walk(base):
      dn[:] = sorted(d for d in dn if d not in SKIP)
      for f in sorted(fn):
        if not f.endswith(".bend"):
          continue
        p = pathlib.Path(dp) / f
        if owned is None or str(p.relative_to(ROOT)) in owned:
          yield p


def span(s: str, open_at: int) -> tuple[int, str]:
  """(end, body) for a `{`-opened construct; `open_at` indexes the `{`."""
  i, depth = open_at, 0
  while i < len(s):
    if s[i] == "{":
      depth += 1
    elif s[i] == "}":
      depth -= 1
      if depth == 0:
        return i, s[open_at + 1:i]
    i += 1
  return len(s), s[open_at + 1:]


def arity_sites(roots, owned=None) -> dict:
  per: dict[int, dict[str, list[int]]] = {}
  for p in files(roots, owned):
    s = p.read_text()
    for m in re.finditer(r"ParamArg\{", s):
      end, body = span(s, m.end() - 1)
      n = len(ts.split_top(re.sub(r"#[^\n]*", "", body)))
      ln = s[:m.start()].count("\n") + 1
      per.setdefault(n, {}).setdefault(str(p.relative_to(ROOT)), []).append(ln)
  return per


def src_sites(roots, owned=None):
  """(file, line, op, class, detail) for every BUFFER/ALLOC/PARAM node construction.

  The three classes are the three spellings the migration leaves, and they are not
  cosmetic distinctions:
    `new.param`            migrated and correct
    `param_src-SELF-LOOP`  `param_src` drops the arena its size node went into, so the
                           index names nothing in the caller's arena and the node's
                           `src[0]` is ITSELF. MEASURED on `mxw_buf`.
    `Nil{}-NO-SIZE`        no size node at all
  """
  rows = []
  for p in files(roots, owned):
    s = p.read_text()
    for start, _end, args in ts.calls(s, p):
      if len(args) != 5 or not ts.KIND.match(args[1]):
        continue
      _arena, op, src, arg, _tag = (a.strip() for a in args)
      if ts.PARAMSRC.match(src):
        cls = "param_src-SELF-LOOP"
      elif src == "Nil{}":
        cls = "Nil{}-NO-SIZE"
      else:
        cls = "explicit-src:" + src[:36]
      rows.append((str(p.relative_to(ROOT)), s[:start].count("\n") + 1,
                   ts.KIND.match(op).group(1), cls, arg[:70]))
    for start, _end, args in ts.calls(s, p, r"\bUOp\.new\.param\("):
      if len(args) == 5 and ts.KIND.match(args[1]):
        rows.append((str(p.relative_to(ROOT)), s[:start].count("\n") + 1,
                     ts.KIND.match(args[1]).group(1), "new.param-MIGRATED", args[2][:40]))
  return rows


def main() -> None:
  ap = argparse.ArgumentParser()
  ap.add_argument("--roots", nargs="*", default=list(DEFAULT_ROOTS))
  ap.add_argument("--all", action="store_true", help="include untracked `*-mut.bend` scratch")
  ap.add_argument("--all-sites", action="store_true", help="print every node site")
  a = ap.parse_args()
  owned = None if a.all else tracked()
  if a.all:
    print("# INCLUDING untracked *-mut.bend scratch (NOT a migration denominator)")
  per = arity_sites(a.roots, owned)
  print("=== ParamArg arity census (whole tree, git-tracked files only) ===")
  for n in sorted(per):
    tot = sum(len(v) for v in per[n].values())
    print(f"arity={n}: sites={tot} files={len(per[n])}")
    for f, lns in sorted(per[n].items(), key=lambda kv: -len(kv[1])):
      shown = ",".join(map(str, lns[:14]))
      more = "..." if len(lns) > 14 else ""
      print(f"  {len(lns):3d} {f}  lines={shown}{more}")
  rows = src_sites(a.roots, owned)
  print(f"\n=== BUFFER/ALLOC/PARAM node constructions: total={len(rows)} ===")
  for cls, n in Counter(r[3] for r in rows).most_common():
    print(f"  {cls}: {n} sites in {len({r[0] for r in rows if r[3] == cls})} files")
  if a.all_sites:
    for f, ln, op, cls, detail in rows:
      print(f"  {f}:{ln} {op} [{cls}] {detail}")


if __name__ == "__main__":
  main()