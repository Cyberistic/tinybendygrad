#!/usr/bin/env python3
"""validate-gate.py -- the lane comparison for `tinybendygrad/uop/validate.bend`.

THE PORT LANE AND THE ORACLE LANE, compared over the row names they SHARE, using
`rebase-gate.py`'s `rows()` -- the one reader. Row names contain no spaces here, but `rows()` is
still the reader rather than a second one: `agent-core.md` records a name-comparing harness
reporting 0 for all 68 mutations in one unit, and a second reader is how that happens.

IT REPORTS FOUR NUMBERS AND NOT A VERDICT WORD, because a verdict word is what let three rows
move in an unadjudicated direction in the first place:

    shared       row names both lanes print -- THE DENOMINATOR for every rate below
    agree        shared rows whose values are byte-identical
    disagree     shared rows whose values differ, listed BY NAME with both values
    port_only / oracle_only    rows with no counterpart, which is a COVERAGE fact, not a pass

`rows()` reads F1 `name=value`, and `row()` in `validate.bend` prints `nm = <blob>` -- the first
`=` splits, so the value is the rest, spaces and `|` included. Both lanes are normalised the same
way, which is checked by `encodings()` below rather than assumed.

    DEV=NULL python3 .agents/slop/validate-gate.py [--port P] [--json]
"""
import argparse
import json
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]


def load_rows_reader():
  """`rebase-gate.py`'s `rows()`, LOADED FROM THE FILE ITSELF.

  It is imported by path rather than by name for two reasons, both measured in this repo: the
  filename is not a legal Python identifier, and `rebase-gate.py` resolves a PINNED interpreter
  at import time (`oracle_py.resolve()`), which is what its header says the verdict must not be
  a function of. A copy of `rows()` here would be a SECOND reader, and a second reader is how a
  harness ends up comparing something other than what the gate compares -- the failure
  `agent-core.md` records as "a name-comparing harness reported 0 for all 68 mutations".
  """
  import importlib.util
  spec = importlib.util.spec_from_file_location("rebase_gate", HERE / "rebase-gate.py")
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m.rows


rows = load_rows_reader()

ORACLE = ".agents/slop/validate-oracle.py"
PORT = "tinybendygrad/uop/validate.bend"


def sh(*a, env=None, timeout=1800):
  return subprocess.run(a, cwd=REPO, capture_output=True, text=True, timeout=timeout,
                        env=dict(os.environ, **(env or {})))


def bend_lane(bend, tries=3):
  """(text, attempts). bend's machine stack overflows on ~1 run in 20 and prints ZERO rows with
  a zero exit status, so an empty lane is re-run and the ATTEMPT COUNT is reported: "0 rows" and
  "0 rows after 3 attempts" are different claims, and only the second is a property of the port."""
  for n in range(1, tries + 1):
    r = sh("./bin/bend", bend, env={"DEV": "NULL"})
    if rows(r.stdout):
      return r.stdout, n
  return r.stdout, tries


def encodings(port_rows, oracle_rows):
  """The two lane ENCODINGS, side by side, for the rows they share. A lane is not comparable
  unless both sides answer the same question, and a shared NAME is not evidence that they do --
  `rebase-gate.py`'s own header records 26 `multi.bend` names that intersected after a `t_`
  strip with 21 DISAGREEING for that reason. So the first rows printed are the values
  themselves, for a reader to compare, and the encoding normalisation is named here."""
  out = ["", "== encodings (shared rows, both sides, first 6) =="]
  for k in list(sorted(set(port_rows) & set(oracle_rows)))[:6]:
    out.append(f"  {k}\n    port  : {port_rows[k]}\n    oracle: {oracle_rows[k]}")
  return out


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--port", default=PORT)
  ap.add_argument("--oracle", default=ORACLE)
  ap.add_argument("--json", action="store_true")
  a = ap.parse_args()

  o = sh(sys.executable, a.oracle, env={"DEV": "NULL"})
  if o.returncode:
    print(f"ORACLE FAILED rc={o.returncode}\n{o.stderr[-2000:]}")
    return 1
  orc = rows(o.stdout)

  ptext, tries = bend_lane(a.port)
  prt = rows(ptext)

  if not orc:
    print("ORACLE PRODUCED ZERO ROWS -- it compared nothing (rebase-gate GUARD 2)")
    return 1
  if not prt:
    print(f"PORT PRODUCED ZERO ROWS after {tries} attempt(s) -- GUARD 2, and the attempt count "
          "is part of the claim")
    return 1

  shared = sorted(set(prt) & set(orc))
  bad = [(k, prt[k], orc[k]) for k in shared if prt[k] != orc[k]]

  lines = [f"port    : {len(prt)} rows",
           f"oracle  : {len(orc)} rows",
           f"shared  : {len(shared)}   <-- THE DENOMINATOR",
           f"agree   : {len(shared) - len(bad)} of {len(shared)}"
           f"   ({100.0 * (len(shared) - len(bad)) / max(1, len(shared)):.1f}%)",
           f"disagree: {len(bad)}",
           f"port only   ({len(set(prt) - set(orc))}): {', '.join(sorted(set(prt) - set(orc))) or '-'}",
           f"oracle only ({len(set(orc) - set(prt))}): "
           f"{', '.join(sorted(set(orc) - set(prt)))[:400] or '-'}"]
  lines += encodings(prt, orc)
  if bad:
    lines += ["", f"== {len(bad)} DISAGREEING ROW(S), BY NAME =="]
    lines += [f"  {k}\n    port  : {x}\n    oracle: {y}" for k, x, y in bad]

  if a.json:
    print(json.dumps({"shared": len(shared), "agree": len(shared) - len(bad),
                      "disagree": [{"row": k, "port": x, "oracle": y} for k, x, y in bad],
                      "port_only": sorted(set(prt) - set(orc)),
                      "oracle_only": sorted(set(orc) - set(prt))}, indent=1))
  else:
    print("\n".join(lines))
  return 0


if __name__ == "__main__":
  sys.exit(main())
