#!/usr/bin/env python
"""The 34-row per-graph census of `runs/graphcmp/D`, plus the CONTROL.

Static only: reads artifact TEXT and one `.py` file's AST. Imports nothing from the
project, compiles nothing, runs no gate, runs no `bend`. `ast.parse` only.

THE POPULATION IS DISCOVERED BY A DIRECTORY WALK, never by a hand list
(doctrine 1, population must be a generator's declaration or a directory walk).

THE CONTROL: the per-graph classification is done by EXACT LABEL, and the resulting
counts are compared against `D0-run-summary.txt`'s own `graphs-agree` /
`graphs-disagree` / `graphs-refused` / `graphs` / `byte-identical`. The instrument
`checks/differ.py` counts with `files_with(pattern, needle)`, which is SUBSTRING
CONTAINMENT (`needle in f.read_text()`). This script computes BOTH ways and prints
whether they differ, so the reader can see that the substring semantics of the
shipped instrument happen to be harmless AT THIS READING rather than assume it.

Writes: graphs.rows, control.rows, summary.rows (all TAB-separated, .rows).
"""
from __future__ import annotations

import ast
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
D = ROOT / "runs" / "graphcmp" / "D"
OUT = pathlib.Path(__file__).resolve().parent

VERDICT = re.compile(r"VERDICT: ([A-Z]+)")


def walk(pattern: str) -> list[pathlib.Path]:
  """Population by DIRECTORY WALK over the artifact dir (doctrine 1b)."""
  return sorted(p for p in D.rglob(pattern) if p.is_file())


def label_of(path: pathlib.Path) -> str:
  """The OPERATIVE verdict: the LAST `# VERDICT: X` in the artifact, taken as an
  exact whole-token label. Empty string means the artifact emitted none -- which is
  what `checks/differ.py`'s `verdict()` also answers, and which it counts REFUSED."""
  found = VERDICT.findall(path.read_text(errors="replace"))
  return found[-1] if found else ""


def state_of(path: pathlib.Path) -> str:
  lab = label_of(path)
  if lab == "AGREE":
    return "AGREE"
  if lab == "DISAGREE":
    return "DISAGREE"
  if lab == "":
    return "REFUSED"
  return f"UNKNOWN-LABEL:{lab}"


def parse_summary() -> dict[str, str]:
  out: dict[str, str] = {}
  for ln in (D / "D0-run-summary.txt").read_text().splitlines():
    if "=" in ln:
      k, _, v = ln.partition("=")
      out[k] = v
  return out


def declared_corpus() -> list[str]:
  """`graphcmp.GRAPHS`' KEYS, read out of the AST without importing the module.

  MEASURED shape: it is a `Dict` whose values are `Name(id='g_<graph>')` references,
  so the module is never executed -- only the constant string keys are lifted out."""
  tree = ast.parse((ROOT / ".agents" / "slop" / "graphcmp.py").read_text())
  for node in tree.body:
    if isinstance(node, ast.Assign) and any(
      isinstance(t, ast.Name) and t.id == "GRAPHS" for t in node.targets
    ):
      return sorted(
        k.value for k in node.value.keys if isinstance(k, ast.Constant)  # type: ignore[attr-defined]
      )
  return []


def main() -> int:
  d1 = walk("D1-graph-*.txt")
  d2 = walk("D2-cmp-*.txt")
  summ = parse_summary()

  rows = []
  for p in d1:
    graph = p.name[len("D1-graph-") : -len(".txt")]
    rows.append((graph, state_of(p), p.name))
  rows.sort()

  counts: dict[str, int] = {}
  for _, st, _ in rows:
    counts[st] = counts.get(st, 0) + 1

  # -- the control, half 1: population agreement with the generator's own declaration
  corpus = declared_corpus()
  walked = sorted(g for g, _, _ in rows)
  pop_ok = walked == corpus

  # -- the control, half 2: my exact-label counts vs the summary's own counters
  mine = {
    "graphs": len(rows),
    "graphs-agree": counts.get("AGREE", 0),
    "graphs-disagree": counts.get("DISAGREE", 0),
    "graphs-refused": counts.get("REFUSED", 0),
  }
  checks = []
  for k, v in mine.items():
    claimed = summ.get(k)
    checks.append((k, str(v), claimed, claimed == str(v)))

  # -- the control, half 3: byte-identical, counted the way differ counts it
  # (LINES containing the marker in the AGGREGATE file) and independently per-graph.
  agg = D / "D2-bytediff.txt"
  agg_lines = sum("BYTE-IDENTICAL" in ln for ln in agg.read_text().splitlines())
  per_graph = sum(
    "CANONICAL BYTE-IDENTICAL" in p.read_text(errors="replace") for p in d2
  )
  bi_claimed = summ.get("byte-identical")
  checks.append(("byte-identical(aggregate lines)", str(agg_lines), bi_claimed,
                 bi_claimed == str(agg_lines)))
  checks.append(("byte-identical(per-graph D2-cmp)", str(per_graph), bi_claimed,
                 bi_claimed == str(per_graph)))

  # -- the control, half 4: would SUBSTRING semantics (differ's own `files_with`)
  # give a different answer from exact labels?  Measured, not assumed.
  sub_agree = sum("VERDICT: AGREE" in p.read_text(errors="replace") for p in d1)
  sub_dis = sum("VERDICT: DISAGREE" in p.read_text(errors="replace") for p in d1)
  sub_differs = (sub_agree, sub_dis) != (mine["graphs-agree"], mine["graphs-disagree"])

  all_ok = pop_ok and all(ok for _, _, _, ok in checks)

  OUT.joinpath("graphs.rows").write_text(
    "".join(f"{g}\t{st}\t{ev}\n" for g, st, ev in rows)
  )
  OUT.joinpath("summary.rows").write_text(
    "".join(f"{k}\t{v}\n" for k, v in sorted(summ.items()))
  )
  OUT.joinpath("control.rows").write_text(
    "".join(
        [
          f"population.walked\t{len(walked)}\n",
          f"population.declared_graphcmp.GRAPHS\t{len(corpus)}\n",
          f"population.identical\t{str(pop_ok).lower()}\n",
          f"population.only_in_walk\t{','.join(sorted(set(walked) - set(corpus))) or '-'}\n",
          f"population.only_in_declared\t{','.join(sorted(set(corpus) - set(walked))) or '-'}\n",
        ]
        + [
          f"count.{k}\tmine={mine_val}\tsummary={claimed}\tmatch={str(ok).lower()}\n"
          for k, mine_val, claimed, ok in checks
        ]
        + [
          f"substring_semantics.agree\t{sub_agree}\n",
          f"substring_semantics.disagree\t{sub_dis}\n",
          f"substring_semantics.differs_from_exact\t{str(sub_differs).lower()}\n",
          f"verdict.control\t{'PASS' if all_ok else 'FAIL'}\n",
        ]
    )
  )

  print(f"population walked={len(walked)} declared={len(corpus)} identical={pop_ok}")
  for k, v, c, ok in checks:
    print(f"  {k:34s} mine={v:>3s} summary={str(c):>3s} match={ok}")
  print(f"  substring(differ semantics) agree={sub_agree} disagree={sub_dis} "
        f"differs_from_exact={sub_differs}")
  print(f"VERDICT control: {'PASS' if all_ok else 'FAIL'}")
  print("states: " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
  return 0 if all_ok else 1


if __name__ == "__main__":
  sys.exit(main())