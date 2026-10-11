#!/usr/bin/env python3
"""THE STALE-CITES CENSUS.  How many `(path, line, must_contain)` style assertions exist in
this tree, and does each one's line number still point at what it claims?

A LINE NUMBER IS A POSITION.  `AGENTS.md` already rejects three other non-populations --
a basename shape, a suffix set, and a hand list -- and a `(path, line, must_contain)`
triple is the third of the same family with the subject swapped: it is a set of
assertions about CONTENT AT A POSITION, so it moves on every edit that changes the
count of lines above it while leaving the text untouched.

**THE POPULATION IS DISCOVERED, NOT NAMED.**  It is a directory walk over every `.py`
file git OWNS (`git ls-tree -r HEAD`), parsed with `ast`, and every literal collection
whose elements carry a string path beside an integer position is admitted regardless of
what the module calls it.  A regex census once reported 183 where the truth was 61;
this one is AST for that reason.  The walk is the population.  Nothing here lists files.

  .agents/slop/stalecites/census.py --report      every instance, with drift
  .agents/slop/stalecites/census.py --json        machine-readable
"""
from __future__ import annotations

import argparse
import ast
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
# THE POPULATION, clause (b): a DIRECTORY WALK over the tree's OWN tracked files, asked of
# git's TREE.  `git ls-files` reads the INDEX, which this tree has had wiped and restaged
# twelve times today; the tree is the only thing that was actually committed.
WALK = ["git", "ls-tree", "-r", "HEAD", "--name-only", "-z"]

# A `(path, line, must_contain)` triple in EITHER spelling: positional 3-tuple, or a dict
# with any of the three roles under any of the usual key names.  Admitting both is the
# point: a census that only knows one shape reports a clean number on a tree that uses
# the other.
KEYLINE = ("line", "lineno", "ln", "row", "at", "line_no")
KEYPATH = ("path", "file", "rel", "target")
KEYTEXT = ("must", "contains", "needle", "text", "want", "expect", "has", "snippet")


def tracked_pys() -> list[Path]:
  out = subprocess.run(WALK, cwd=ROOT, capture_output=True, text=True, check=True).stdout
  return [ROOT / p for p in out.split("\0") if p.endswith(".py")]


def _str(node: ast.AST) -> str | None:
  return node.value if isinstance(node, ast.Constant) and isinstance(node.value, str) else None


def _int(node: ast.AST) -> int | None:
  return node.value if isinstance(node, ast.Constant) and isinstance(node.value, int) else None


def _get(d: dict[str, ast.AST], names: tuple[str, ...]) -> ast.AST | None:
  for k in names:
    if k in d:
      return d[k]
  return None


def _is_pathish(s: str) -> bool:
  """A path in this tree, by SHAPE OF THE STRING -- the one shape claim that is safe,
  because it is only ever used to ADMIT a candidate, never to conclude one."""
  return bool(re.search(r"[/\\]|\.(py|bend|mjs|sh|md|rows|tsv|json|toml|c|js)\b", s))


def _is_lineish(node: ast.AST) -> int | None:
  """An integer in 1..2**20 -- a POSITION.  Not every integer in a collection is a line,
  so the caller also requires a path beside it; the two together are the shape."""
  n = _int(node)
  return n if n is not None and 1 <= n <= (1 << 20) else None


def instances(path: Path) -> list[dict]:
  """Every literal collection in `path` that carries (path, line, text).  Returns one
  record per ELEMENT, so the denominator is ASSERTIONS and not MODULES."""
  try:
    tree = ast.parse(path.read_text(), filename=str(path))
  except (SyntaxError, ValueError, UnicodeDecodeError):
    return []
  rel = str(path.relative_to(ROOT))
  out: list[dict] = []

  def examine(elts: list[ast.AST], owner: str, owner_line: int) -> None:
    for e in elts:
      if isinstance(e, (ast.Tuple, ast.List)) and len(e.elts) >= 3:
        s = [_str(x) for x in e.elts]
        i = [_is_lineish(x) for x in e.elts]
        # (path, line, ...) -- positional, in either order, with the anchor taken from the
        # LAST string element that is not the path.  3-tuples and 6-tuples alike.
        for pi, ti in ((0, 1), (1, 0)):
          if (s[pi] and _is_pathish(s[pi]) and i[ti] is not None):
            # EVERY element after the position must be a SCALAR constant.  A test vector
            # like `("gate.py", 0, ["--plant"], [], "a scenario")` carries argv Lists and
            # its integer is a CASE INDEX, not a line -- it is admitted by a looser shape
            # test and is not a citation.  Scalars-only is the structural discriminator;
            # guessing from the prose would be the same regex census that reported 183.
            if not all(isinstance(x, ast.Constant) for x in e.elts):
              break
            # WHICH element is the anchor is a CONVENTION, and this tree uses two:
            # `(path, line, must)` and `(path, line, must, why)` put it right after the
            # position; `(path, line, ref, N, end, anchor)` puts it last.  LAST IS TRIED
            # FIRST because it is the form whose convention the module DECLARES in its own
            # comment ("Anchor is a literal substring that MUST be on the cited line"),
            # and the other form's last element is prose rationale that resolves nowhere.
            # Guessing one invented 14 phantom NO-ANCHORs; guessing the other let a
            # filename field shadow the anchor (measured, this run).  Which one matched is
            # reported, so the shape is visible rather than assumed.
            cands: list[str] = []
            for k in (len(e.elts) - 1, ti + 1):
              v = s[k] if 0 <= k < len(s) else None
              if v and v not in cands:
                cands.append(v)
            if not cands:
              break
            out.append(dict(file=rel, owner=owner, owner_line=owner_line, shape="tuple",
                            line=i[ti], target=s[pi], texts=cands))
            break
        else:
          _dict(e, owner, owner_line)
      elif isinstance(e, ast.Dict):
        _dict(e, owner, owner_line)

  def _dict(node: ast.AST, owner: str, owner_line: int) -> None:
    if not isinstance(node, ast.Dict):
      return
    d = {}
    for k, v in zip(node.keys, node.values):
      key = _str(k) if k is not None else None
      if key:
        d[key] = v
    lp = _get(d, KEYPATH)
    ll = _get(d, KEYLINE)
    lt = _get(d, KEYTEXT)
    if lp is None or ll is None:
      return
    sp, sl, st = _str(lp), _is_lineish(ll), _str(lt) if lt is not None else None
    if sp and sl is not None and _is_pathish(sp) and st:
      out.append(dict(file=rel, owner=owner, owner_line=owner_line, shape="dict",
                      line=sl, target=sp, texts=[st]))

  for node in ast.walk(tree):
    if isinstance(node, (ast.Assign, ast.AnnAssign)):
      val = node.value
      if isinstance(val, (ast.Tuple, ast.List)):
        owner = (ast.unparse(node.targets[0]) if isinstance(node, ast.Assign)
                 else ast.unparse(node.target))
        examine(val.elts, owner, node.lineno)
      elif isinstance(val, ast.Dict):
        owner = (ast.unparse(node.targets[0]) if isinstance(node, ast.Assign)
                 else ast.unparse(node.target))
        _dict(val, owner, node.lineno)
      elif isinstance(val, ast.Call) and getattr(val.func, "id", "") in ("dict", "OrderedDict"):
        owner = (ast.unparse(node.targets[0]) if isinstance(node, ast.Assign)
                 else ast.unparse(node.target))
        for kw in val.keywords:
          if kw.arg:
            d = {kw.arg: kw.value}
            lp, ll, lt = _get(d, KEYPATH), _get(d, KEYLINE), _get(d, KEYTEXT)
            sp = _str(lp) if lp is not None else None
            sl = _is_lineish(ll) if ll is not None else None
            st = _str(lt) if lt is not None else None
            if sp and sl is not None and _is_pathish(sp) and st:
              out.append(dict(file=rel, owner=owner, owner_line=node.lineno, shape="dict()",
                              line=sl, target=sp, texts=[st]))
  return out


def source(rel: str) -> str | None:
  """A `rev:path` row names a BLOB, not a file.  It has to: a re-vendor moved the very
  lines this project cites, and a citation about upstream survives only if it reads the
  blob.  Copied from `checks/disagree-gate.py`, which is where the form was introduced."""
  if ":" not in rel:
    p = ROOT / rel
    return p.read_text() if p.exists() else None
  rev, path = rel.split(":", 1)
  r = subprocess.run(["git", "show", f"{rev}:{path}"], cwd=ROOT,
                     capture_output=True, text=True)
  return r.stdout if r.returncode == 0 else None


def hits(text: str, needle: str) -> list[int]:
  """Every line carrying the needle as a WHOLE TOKEN -- the same `cited()` rule the gate
  under repair uses, so the two agree by construction instead of by coincidence."""
  rx = re.compile(re.escape(needle) + r"(?![\w])")
  return [i for i, l in enumerate(text.splitlines(), 1) if rx.search(l)]


def judge(rec: dict) -> dict:
  text = source(rec["target"])
  rec.update(status="NO-FILE", found=[], drift=None, n_hits=0, unique=False, matched=None)
  if text is None:
    return rec
  # TRY EVERY CANDIDATE ANCHOR, take the first that resolves, and REPORT which one.  A
  # 4-tuple's second string is the rationale and its 3-tuple's is the anchor; scoring
  # only one convention is how a census invents 14 phantoms (measured, this run).
  for cand in rec["texts"]:
    h = hits(text, cand)
    if not h:
      continue
    rec.update(text=cand, n_hits=len(h), found=h[:8], unique=len(h) == 1)
    if rec["line"] in h:
      rec["status"] = "ON-LINE"
    else:
      rec["status"] = "DRIFT"
      rec["drift"] = h[0] - rec["line"]
    rec["matched"] = cand
    return rec
  rec["status"] = "NO-ANCHOR"
  rec["text"] = rec["texts"][0]
  return rec


def census() -> list[dict]:
  recs: list[dict] = []
  for p in tracked_pys():
    recs += [judge(r) for r in instances(p)]
  return recs


def report(recs: list[dict]) -> None:
  pys = tracked_pys()
  by_status: dict[str, list[dict]] = {}
  for r in recs:
    by_status.setdefault(r["status"], []).append(r)
  print(f"POPULATION  : directory walk over {len(pys)} git-tracked .py files "
        f"(git ls-tree -r HEAD), parsed with ast")
  print(f"ASSERTIONS  : {len(recs)} (path, line, must_contain)-shaped literals")
  print(f"MODULES     : {len({r['file'] for r in recs})}")
  print()
  order = ("ON-LINE", "DRIFT", "NO-ANCHOR", "NO-FILE")
  for s in order:
    n = len(by_status.get(s, []))
    print(f"  {s:<10} {n:>4}  of {len(recs)}")
  print()
  for s in ("DRIFT", "NO-ANCHOR", "NO-FILE"):
    rs = by_status.get(s, [])
    if not rs:
      continue
    print(f"--- {s} ({len(rs)}) ---")
    for r in sorted(rs, key=lambda x: (x["file"], x["owner_line"])):
      print(f"  {r['file']}:{r['owner_line']} {r['owner']}  ->  {r['target']}:{r['line']} "
            f"~{r['text'][:44]!r}")
      print(f"      status={r['status']} n_hits={r['n_hits']} unique={r['unique']} "
            f"found={r['found'][:6]} drift={r['drift']}")
  print()
  dupes = {r["target"] for r in recs}
  print(f"STALE ASSERTIONS: {len(by_status.get('DRIFT', [])) + len(by_status.get('NO-ANCHOR', []))}"
        f" of {len(recs)}")


def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
  ap.add_argument("--json", action="store_true")
  ap.add_argument("--report", action="store_true")
  a = ap.parse_args()
  recs = census()
  if a.json:
    print(json.dumps(recs, indent=2))
  else:
    report(recs)
  # PASS 0 / FAIL 1: an instance whose position no longer points at its claim is a
  # measured disagreement, not a note.
  bad = [r for r in recs if r["status"] in ("DRIFT", "NO-ANCHOR", "NO-FILE")]
  return 1 if bad else 0


if __name__ == "__main__":
  raise SystemExit(main())