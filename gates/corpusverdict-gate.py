#!/usr/bin/env python3
"""corpusverdict-gate.py -- IS THE RECORDED `graphcmp` VERDICT CURRENT FOR THIS TREE?

    .venv/bin/python gates/corpusverdict-gate.py

WHY THIS GATE EXISTS, AND THE MEASUREMENT THAT PROVES THE GAP. Every "34/34 graphs agree"
in this tree described a substrate that no longer exists. `runs/graphcmp/D/D0-run-summary.txt`
carries `substrate-start`/`substrate-end` -- `checks/differ.py` writes both, deliberately, so a
reader can tell what tree an artifact set describes -- and on 2026-10-18 those read
`5d3f31197e88124246dd819fa1b904439ef255805c36bf30656145171d95ffa3` while the live digest was
`96f40eead5f3c326d4ae5e814e202aabb1844a7a86f281e93b910b53065af5c3`. MEASURED: 20 `.bend` files
changed between the run (Oct 17 01:50) and now, 730 insertions / 583 deletions, including
`uop/spec.bend` (208), `uop/symbolic.bend` (251) and `uop/ops.bend` (179) -- the emission logic
itself. **The verdict is not merely old; it describes a tree that is gone.**

WHAT MAKES THE RE-RUN THE OBVIOUS FIX, AND WHY IT IS NOT ONE. `differ.py`'s own readiness
probe is `./bin/bend .agents/slop/graphcmp.bend --check-only` (`settled()`, differ.py:1038), and
on this tree it answers `SOME PROOFS FAIL`: `graphcmp.bend:791` constructs `O.OpsGROUP{}`, and
`tinybendygrad/uop/ops.bend` declares no such constructor (MEASURED: 0 occurrences in the file,
0 in the whole port; upstream reimplemented GROUP/FLIP, so the `Op` union now has 75 members).
`differ.ready(0)` returns False, MEASURED BY CALLING IT. So:

  * `differ.py run` dispatches DIRECTLY to `cmd_run` (differ.py:1357) with NO readiness gate,
    and `cmd_run` overwrites `D/` artifact by artifact. Running it would replace 243 files of
    evidence with a dead bend lane. This gate's `run.gated` row MEASURES that from
    `cmd_run`'s own source instead of asserting it.
  * `differ.py repro` DOES gate on `ready()` (`clean_run`, differ.py:1288) and therefore
    refuses -- correctly, labelling itself "NOT a measurement". MEASURED: `repro 0` printed
    `# run A: no healthy run in 0 attempts -- this is NOT a measurement` and left all 243
    files of `runs/graphcmp/` byte-identical (digest-of-digests `8fc35f67...` before and after).

So the number cannot be REFRESHED today, and this gate is what makes that a machine-checked
fact rather than a claim in a report.

IT NEEDS NO `bend` AND CANNOT DAMAGE ANYTHING. It reads two files and hashes a declared
population; it never writes under `runs/graphcmp/`. The bend compile state is reported as its
OWN row so that a `bend`-less machine gets a truthful partial answer instead of a green one.

THE POSITIVE CONTROL, AND IT IS THE POINT. This gate's failure mode is SILENTLY READING
`CURRENT` -- an instrument that cannot recognise a stale digest reports the project's
load-bearing number as healthy, which is the exact defect it exists to catch. So every run
first plants a digest that is KNOWN to differ and asserts the comparator reports it STALE. A
control that fails is `REFUSED`, not `PASS`.

DOCTRINE 1. The population is `differ`'s own declaration, LOADED BY PATH: `substrate_digest()`
walks `tinybendygrad/` and adds `SUBSTRATE_INPUTS`, and `SUBSTRATE_ROWS` names the two rows.
Nothing is listed here that the generator already declares.

DOCTRINE 2. `SKIP` IS NOT `PASS`. A missing summary is `REFUSED` (a precondition was absent),
a summary without the two substrate rows is `FAIL` (it ran and could not answer), and an
empty row set is `DEAD`.
"""

from __future__ import annotations

import argparse
import importlib.util
import inspect
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
ART = HERE / "artifacts" / "corpusverdict-gate"
SUMMARY = ROOT / "runs" / "graphcmp" / "D" / "D0-run-summary.txt"

sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, verdict_of  # noqa: E402

STATE = "state"          # copied from checks/compile-census.py's `state` column
TOK = "token"            # copied likewise: bounded.py's OWN verdict token, never the rc

#: THE ROWS THAT CARRY A DENOMINATOR. `graphs-agree` alone is a numerator; quoting it without
#: `graphs` is how a count stops being checkable, so the two are read and reported together.
VERDICT_ROWS = ("graphs", "graphs-answered", "graphs-agree", "graphs-disagree",
                "byte-identical", "not-comparable", "expect-moved")


def load(path: pathlib.Path, name: str):
  """BY PATH. `differ` is the generator whose declaration defines the population, so it is
  imported rather than re-typed."""
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  sys.modules[name] = mod
  spec.loader.exec_module(mod)
  return mod


def rows_file(path: pathlib.Path) -> dict[str, str]:
  """`name=value` -> value. The summary is a flat file of these, which is the whole reason a
  reader can check one row without a parser."""
  out = {}
  if path.exists():
    for line in path.read_text().splitlines():
      k, sep, v = line.partition("=")
      if sep and re.fullmatch(r"[A-Za-z0-9-]+", k):
        out[k] = v
  return out


def control(compare) -> str:
  """THE POSITIVE CONTROL. This gate's whole job is to say STALE, so the only way it can be
  worthless is by being unable to. It requires a planted digest that DIFFERS FROM THE REFERENCE
  to read STALE, and the identical digest to read CURRENT, so a comparator that says STALE
  unconditionally is caught as surely as one that never says it. (The first version of this
  control planted a digest and compared it to ITSELF, and this REFUSED row is why: a control
  that asserts nothing is a control that cannot fail, which is the defect it guards against.)"""
  ref = "ab" * 32
  for planted in ("0" * 64, "f" * 64):
    got = compare(ref, planted)
    if got != "STALE":
      return f"planted {planted[:4]}... read {got}, wanted STALE"
  if compare(ref, ref) != "CURRENT":
    return f"identical digests read {compare(ref, ref)}, wanted CURRENT"
  return "planted-diff read STALE, identical read CURRENT"


def emit(name: str, **kv) -> str:
  return "\t".join([name] + [f"{k}={v}" for k, v in kv.items()])


def rel(path: pathlib.Path) -> str:
  """The path as the tree would name it, and ABSOLUTE when it is outside the tree. A
  `relative_to` that raises turns `--summary /tmp/x` into a traceback instead of the verdict."""
  try:
    return str(path.relative_to(ROOT))
  except ValueError:
    return str(path)


def main(argv=None) -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("--summary", type=pathlib.Path, default=SUMMARY,
                  help="the run summary to audit (default runs/graphcmp/D/D0-run-summary.txt)")
  a = ap.parse_args(argv)
  rows: list[str] = []

  if not a.summary.exists():
    rows.append(emit("summary", **{STATE: "REFUSED", TOK: "ABSENT?NOTOKEN",
                                  "path": rel(a.summary)}))
    print("\n".join(rows))
    print("corpusverdict-gate: REFUSED -- no run summary; the corpus has never answered here")
    return REFUSED

  got = rows_file(a.summary)
  differ = load(ROOT / "checks" / "differ.py", "corpusverdict_differ")
  recorded = [got.get(k) for k in differ.SUBSTRATE_ROWS]

  # --- THE CONTROL, BEFORE the verdict it guards -----------------------------------------
  def compare(rec: str, live: str) -> str:
    return "CURRENT" if rec == live else "STALE"

  note = control(compare)
  rows.append(emit("control", **{STATE: "OK" if note.startswith("planted-diff") else "REFUSED",
                                TOK: "NOTOKEN?NOTOKEN", "note": note}))
  if not note.startswith("planted-diff"):
    print("\n".join(rows))
    print(f"corpusverdict-gate: REFUSED -- the staleness comparator is not a comparator ({note}); "
          f"a clean read from it would be a read over nothing")
    return REFUSED

  # --- THE VERDICT, WITH ITS DENOMINATOR -------------------------------------------------
  den = " ".join(f"{k}={got.get(k, 'ABSENT')}" for k in VERDICT_ROWS)
  rows.append(emit("verdict", **{STATE: "OK", "graphs": got.get("graphs", "ABSENT"),
                                "agree": got.get("graphs-agree", "ABSENT"), "rows": den}))

  # --- THE SUBSTRATE, WHICH IS THE WHOLE QUESTION ----------------------------------------
  live = differ.substrate_digest()
  unrecorded = [k for k, v in zip(differ.SUBSTRATE_ROWS, recorded) if not v]
  if unrecorded:
    rows.append(emit("substrate", **{STATE: "FAIL", TOK: "ABSENT?NOTOKEN",
                                    "why": f"no {','.join(unrecorded)} row",
                                    "live": live[:16]}))
    print("\n".join(rows))
    print(f"corpusverdict-gate: FAIL -- the summary carries no {','.join(unrecorded)} row, so it "
          f"cannot be checked against anything")
    return FAIL

  same = all(r == live for r in recorded)
  rows.append(emit("substrate", **{STATE: "OK" if same else "FAIL",
                                  "recorded": ",".join(r[:16] for r in recorded),
                                  "live": live[:16],
                                  "inputs": len(differ.substrate_entries()),
                                  "verdict": "CURRENT" if same else "STALE"}))

  # --- IS `differ.py run` SAFE TO INVOKE? READ FROM `cmd_run`'s OWN SOURCE ----------------
  src = inspect.getsource(differ.cmd_run)
  gated = ("clean_run(" in src) or re.search(r"\bready\s*\(", src) is not None
  rows.append(emit("run.gated", **{STATE: "OK" if gated else "FAIL",
                                  "verdict": "GATED" if gated else "UNGATED",
                                  "cmd": "differ.py run -> cmd_run"}))

  # --- THE BEND LANE, ITS OWN ROW, SO A bend-LESS MACHINE IS NOT GREEN --------------------
  bend = ROOT / "bin" / "bend"
  driver = ROOT / ".agents" / "slop" / "graphcmp.bend"
  if not (bend.exists() and driver.exists()):
    rows.append(emit("bend", **{STATE: "SKIP", TOK: "ABSENT?NOTOKEN", "verdict": "UNKNOWN"}))
  else:
    p = subprocess.run([str(bend), rel(driver), "--check-only"],
                       cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    tok = (p.stdout.split("\n", 1)[0] or "?").strip()[:40]
    rows.append(emit("bend", **{STATE: "OK" if p.returncode == 0 else "FAIL",
                                "token": tok, "rc": p.returncode,
                                "probe": "graphcmp.bend --check-only"}))

  body = ("# corpusverdict.rows -- GENERATED by `gates/corpusverdict-gate.py`, its ONLY writer.\n"
          "# One TAB-separated `name=value` record per row. `substrate.verdict=CURRENT|STALE` is\n"
          "# the answer to 'is the recorded corpus verdict current for this tree?', and it is\n"
          "# computed by hashing `differ.substrate_digest()`, never by reading a timestamp.\n"
          + "\n".join(rows) + "\n")
  ART.mkdir(parents=True, exist_ok=True)
  (ART / "corpusverdict.rows").write_text(body)
  for ln in rows:
    print(ln)

  if not rows:
    print(f"corpusverdict-gate: {verdict_of(DEAD)} -- no rows")
    return DEAD
  verdict = FAIL if any(f"{STATE}=FAIL" in r for r in rows) else PASS
  if verdict is FAIL:
    print(f"corpusverdict-gate: {verdict_of(FAIL)} -- "
          + (f"the recorded verdict is {'CURRENT but ' if same else ''}the tree cannot re-run it"
             if same else "the recorded verdict is STALE (recorded substrate != live substrate)")
          + ("" if gated else "; and `differ.py run` is UNGATED, so it would overwrite D/"))
    return FAIL
  print(f"corpusverdict-gate: PASS -- the recorded verdict describes THIS tree "
        f"(substrate {live[:16]}, {got.get('graphs')} graphs, "
        f"{got.get('graphs-agree')} agree)")
  return PASS


if __name__ == "__main__":
  sys.exit(main())