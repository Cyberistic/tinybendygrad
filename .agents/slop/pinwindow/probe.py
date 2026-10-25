#!/usr/bin/env python3
"""THE ATTRIBUTION QUESTION, MEASURED ON ONE FROZEN PORT TREE.

    .venv/bin/python .agents/slop/pinwindow/probe.py

`gates/pin-cite-gate.py`'s `window_tokens()` decides WHICH CITATION a backticked name
belongs to, and therefore WHICH ROW a claim token is judged under. This probe runs the
gate's OWN census, ON ONE FROZEN COPY OF THE PORT TREE, under FOUR rules for that
decision, and reports the class counts and the row-level movement for each.

THE FOUR RULES.
  OLD     the shipped rule: keep the name for citation `i` when the name is within
          `_NEAREST` of some OTHER citation. The name therefore goes to the FARTHER
          citations and is DROPPED from the nearest one.
  NEAREST the docstring's rule: the name belongs to the citation(s) nearest to it; a
          tie belongs to BOTH.
  NEAREST+CUTOFF  NEAREST, and a name farther than `_NEAREST` from EVERY citation on
          its line belongs to NONE of them.
  NEAREST+CUTOFF-1  the same, but the cutoff is only consulted when the line carries
          MORE THAN ONE citation -- which is where the ambiguity is.

THE TREE IS FROZEN. `gates/pin-cite-gate.py --tree DIR` exists for exactly this: the
port tree is owned by other units and moves under the gate's feet, so a before/after
reading taken at two different moments compares two different trees.
"""

from __future__ import annotations

import collections
import importlib.util
import sys
import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GATE = ROOT / "gates" / "pin-cite-gate.py"
TREE = Path(__file__).resolve().parent / "frozen"


def load(path: Path, name: str):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    spec.loader.exec_module(mod)
  return mod


pc = load(GATE, "pc_probe")
census = pc.load_census()
CORPUS = census.Upstream(pc.UPSTREAM)
PIN = pc.declared_pin()


# --------------------------------------------------------------------------- the rules

def _tokens(out: list[str], text: str) -> None:
  for t in pc.IDENT.findall(text):
    if len(t) < 3 or t.lower() in pc.KEYWORDS:
      continue
    if t not in out:
      out.append(t)


def rule_old(line: str, spans, i: int) -> list[str]:
  """THE SHIPPED RULE, verbatim."""
  if i >= len(spans):
    return []
  pos = sorted(enumerate(spans), key=lambda t: t[1][0])
  out: list[str] = []
  for m in pc.BACKTICK.finditer(line):
    if pc.CITE_SPAN.search(m.group(1)):
      continue
    if len(pos) > 1:
      gap = min(max(0, s - m.end(), m.start() - e) for j, (s, e) in pos if j != i)
      if gap > pc._NEAREST:
        continue
    _tokens(out, m.group(1))
  return out


def _nearest(line: str, spans, i: int, cutoff: bool, cutoff_when_many: bool) -> list[str]:
  if i >= len(spans):
    return []
  out: list[str] = []
  for m in pc.BACKTICK.finditer(line):
    if pc.CITE_SPAN.search(m.group(1)):
      continue
    gaps = [max(0, s - m.end(), m.start() - e) for (s, e) in spans]
    if not gaps:
      continue
    best = min(gaps)
    if cutoff and (not cutoff_when_many or len(spans) > 1) and best > pc._NEAREST:
      continue
    if gaps[i] != best:
      continue
    _tokens(out, m.group(1))
  return out


def rule_nearest(line, spans, i):
  return _nearest(line, spans, i, cutoff=False, cutoff_when_many=False)


def rule_nearest_cutoff(line, spans, i):
  return _nearest(line, spans, i, cutoff=True, cutoff_when_many=False)


def rule_nearest_cutoff1(line, spans, i):
  return _nearest(line, spans, i, cutoff=True, cutoff_when_many=True)


def rule_self_near(line, spans, i):
  """A name belongs to a citation IFF IT IS WITHIN `_NEAREST` OF IT."""
  if i >= len(spans):
    return []
  out: list[str] = []
  for m in pc.BACKTICK.finditer(line):
    if pc.CITE_SPAN.search(m.group(1)):
      continue
    gap = max(0, spans[i][0] - m.end(), m.start() - spans[i][1])
    if gap > pc._NEAREST:
      continue
    _tokens(out, m.group(1))
  return out


def rule_each_side(line, spans, i):
  """A name belongs to the NEAREST citation on its LEFT and the nearest on its RIGHT."""
  if i >= len(spans):
    return []
  out: list[str] = []
  for m in pc.BACKTICK.finditer(line):
    if pc.CITE_SPAN.search(m.group(1)):
      continue
    gaps = [max(0, s - m.end(), m.start() - e) for (s, e) in spans]
    if not gaps:
      continue
    left = [g for g in gaps if g == min([x for x in gaps if x], default=0)]
    best_left = min((g for j, g in enumerate(gaps) if spans[j][1] <= m.start()), default=None)
    best_right = min((g for j, g in enumerate(gaps) if spans[j][0] >= m.end()), default=None)
    mine = []
    if best_left is not None and gaps[i] == best_left:
      mine.append("left")
    if best_right is not None and gaps[i] == best_right:
      mine.append("right")
    if not mine:
      continue
    _tokens(out, m.group(1))
  return out


RULES = {
  "OLD": rule_old,
  "NEAREST": rule_nearest,
  "NEAREST+CUTOFF": rule_nearest_cutoff,
  "NEAREST+CUTOFF-1": rule_nearest_cutoff1,
  "SELF-NEAR": rule_self_near,
  "EACH-SIDE": rule_each_side,
}


# --------------------------------------------------------------------------- the run

def run(window_fn) -> tuple[list[dict], dict]:
  pc.window_tokens = window_fn
  up, _local = pc.collect(census, TREE)
  pc.resolve_all(census, up, CORPUS, PIN)
  return up, pc.classify(up)


def counts(up: list[dict], cls: dict) -> dict[str, int]:
  return {
    "cite.total": len(up),
    "cite.checkable": len(cls["checkable"]),
    "cite.uncheckable_no_claim_token": len(cls["uncheckable"]),
    "cite.at_pin": len(cls["at_pin"]),
    "cite.only_older_revision": len(cls["only_older"]),
    "cite.at_no_revision": len(cls["nowhere"]),
    "cite.at_no_revision_dangling": len(cls["dangling"]),
    "cite.ambient_relocated": len(cls["relocated"]),
    "cite.unverifiable_no_claim_about_the_file": len(cls["unverifiable"]),
    "cite.upstream_removed": len(cls["removed"]),
  }


def key(c: dict) -> str:
  return f"{c['rel']}:{c['at']} {c['subject']}:{c['lo']}"


def main() -> int:
  runs: dict[str, tuple[list[dict], dict]] = {}
  for name, fn in RULES.items():
    up, cls = run(fn)
    runs[name] = (up, cls)
    print(f"== {name}")
    for k, v in counts(up, cls).items():
      print(f"   {k}={v}")
    print()

  base_up, base_cls = runs["OLD"]
  for name in ("NEAREST", "NEAREST+CUTOFF", "NEAREST+CUTOFF-1"):
    up, cls = runs[name]
    moved = [(b, a) for b, a in zip(base_up, up)
             if pc.row_class(b) != pc.row_class(a) or b["toks"] != a["toks"]]
    classes = collections.Counter((pc.row_class(b), pc.row_class(a)) for b, a in moved)
    print(f"== MOVEMENT OLD -> {name}: {len(moved)} of {len(up)} rows changed")
    for (x, y), n in sorted(classes.items(), key=lambda kv: -kv[1]):
      print(f"   {x:28s} -> {y:28s} {n}")
    print()

  # THE CLASS COUNTS, SIDE BY SIDE.
  names = list(RULES)
  print("== THE CLASS COUNTS, SIDE BY SIDE")
  keys = list(counts(*runs["OLD"]))
  print("   " + "class".ljust(46) + "".join(n.rjust(18) for n in names))
  for k in keys:
    row = "   " + k.ljust(46)
    for n in names:
      up, cls = runs[n]
      row += str(counts(up, cls)[k]).rjust(18)
    print(row)
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
