#!/usr/bin/env python3
"""The two lanes side by side, and the count of where they differ. A MAP, not a verdict.

    .venv/bin/python gates/specreach-compare.py            # print
    .venv/bin/python gates/specreach-compare.py --out gates/specreach-map.rows

TWO LANES, TWO BUILDERS. `gates/specreach.bend` mints three fixtures in the PORT and reads all six
tables; `gates/specreach-oracle.py` mints the same three in CPython from upstream's own constructors.
Neither file knows about the other, so a disagreement is evidence about the port rather than an
artefact of one implementation meeting itself -- which is the reason `opseven.bend`/`opseven-oracle.py`
are two files and this pair follows the same shape.

WHY THE PORT'S LANE RUNS UNDER `checks/bounded.py`. `bend` is the memory-heavy half of this tree (the
per-file peaks are in `.agents/slop/peakrss/census.rows`) and three other units were compiling while
this ran, so the run is a single child under a 2048 MB ceiling and the verdict is read off the
`[bounded]` TOKEN, never the exit status. MEASURED peak for this probe: 750 MB, `WITHIN-LIMITS`, 2 s.

WHAT THE OUTPUT IS FOR. Nothing here decides whether a disagreement is acceptable. `spec_full` is
upstream's semantics, so a disagreement is a fact to be reported with both numbers attached, and this
file prints them; freezing either side as "the contract" is what `AGENTS.md` calls a gate that cannot
fail. `gates/specreach-gate.py` is the VERDICT on these cells and on the tag spaces; this file stays
the map.

THE ADJUDICATION OF THE THREE `sf` CELLS, because the map used to read as a PORT defect and the
reader deserves the answer. It WAS the port, and it was ONE def: `fu_block.go`'s three thresholds
each read ONE MORE than the block base they select, so a block's FIRST rule was dispatched into the
PREVIOUS block's ladder, where that ladder's `case _` arm handed it to a rule that does not apply
to it -- `spec_hcq`'s GETADDR rule (`spec.py:230`) to `spec_shared`'s SINK rule (`spec.py:50`), and
`spec_program`'s first rule (`spec.py:206`) to no rule at all. The port's RULE BODIES were right all
along, and the `DISPATCH:` rows below are the proof: `hq0` answered True and `pr0` answered False on
the very fixtures whose `sf` row read `9`. The oracle was measuring the same six tables upstream
composes, so it was NOT measuring less. MEASURED, both lanes, before and after:
`gates/specreach-map.rows` read `DIFFER over 18 cells: 3` and reads `0`. The `--out` file is a READING with the two hashes that produced it in its header, so the next run
is a diff against a stated tree rather than against an impression.

NO `__main__` GUARD, ON PURPOSE: `gates/gates-pop.py` discovers gates by that AST node, and this is a
census, not a gate.
"""
import argparse
import hashlib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HERE = ROOT / "gates"
PY = ROOT / ".venv" / "bin" / "python"
BOUNDED = ROOT / "checks" / "bounded.py"
BENDLOCK = ROOT / "checks" / "bendlock.sh"
BEND = ROOT / "bin" / "bend"
PROBE = HERE / "specreach.bend"
ORACLE = HERE / "specreach-oracle.py"
# the keys both lanes print, in the order the port prints them
KEYS = ("sh", "te", "sp", "hq", "sk", "sf")


def sha(path: Path) -> str:
  return hashlib.sha256(path.read_bytes()).hexdigest()[:16]


def rows(text: str) -> dict[str, dict[str, str]]:
  out: dict[str, dict[str, str]] = {}
  for line in text.splitlines():
    if "=" not in line:
      continue
    name, rest = line.split("\t", 1) if "\t" in line else line.split("=", 1)[0], line.split("\t", 1)[-1] \
        if "\t" in line else ""
    cells = {}
    for tok in (rest if "\t" in line else line).replace("\t", " ").split():
      if "=" in tok:
        k, v = tok.split("=", 1)
        cells[k] = v
    if cells:
      out[name] = cells
  return out


def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("--out", type=Path, help="write the reading here")
  args = ap.parse_args()

  bd = subprocess.run([str(BENDLOCK), "--", str(PY), str(BOUNDED), "--mb", "2048", "--",
                       str(BEND), str(PROBE)], capture_output=True, text=True, cwd=ROOT)
  token = next((l for l in bd.stderr.splitlines() if l.startswith("[bounded]")), "[bounded] NOT RUN")
  if "WITHIN-LIMITS" not in token:
    print(token)
    print(bd.stderr[-800:])
    return 1
  cp = subprocess.run([str(PY), str(ORACLE)], capture_output=True, text=True, cwd=ROOT)
  if cp.returncode != 0:
    print(cp.stderr[-800:])
    return 1

  port_rows: dict[str, dict[str, str]] = {}
  for line in bd.stdout.splitlines():
    if "=" not in line:
      continue
    name, _, cells = line.partition("=")
    prefix, _, key = name.rpartition("_")
    port_rows.setdefault(prefix, {})[key] = cells
  cpy_rows = {l.split("\t")[0]: dict(t.split("=") for t in l.split("\t")[1].split())
              for l in cp.stdout.splitlines() if "\t" in l}

  lines = [f"# gates/specreach-compare.py reading",
           f"#   probe.bend={sha(PROBE)} oracle.py={sha(ORACLE)} "
           f"spec.bend={sha(ROOT / 'tinybendygrad/uop/spec.bend')} ops.bend={sha(ROOT / 'tinybendygrad/uop/ops.bend')}",
           f"#   {token.strip()}",
           "# fixture\tkey\tport\tcpython\tagree"]
  differ = 0
  for fixture in sorted(set(port_rows) | set(cpy_rows)):
    for key in KEYS:
      pv = port_rows.get(fixture, {}).get(key, "?")
      cv = cpy_rows.get(fixture, {}).get(key, "?")
      same = pv == cv
      differ += 0 if same else 1
      lines.append(f"{fixture}\t{key}\t{pv}\t{cv}\t{'yes' if same else 'NO'}")
  lines.append(f"# DIFFER over {len(KEYS) * len(set(port_rows) | set(cpy_rows))} cells: {differ}")
  # the port's own extra rows: the per-TAG dispatch answers, which have no CPython counterpart because
  # CPython's fold does not dispatch by tag at all -- so they are reported, never diffed.
  for fixture in sorted(port_rows):
    for key in sorted(k for k in port_rows[fixture] if k not in KEYS):
      lines.append(f"{fixture}\tDISPATCH:{key}\t{port_rows[fixture][key]}\t-\tport-only")
  out = "\n".join(lines)
  print(out)
  if args.out:
    args.out.write_text(out + "\n")
  return 0

# NO `if __name__ == "__main__"` GUARD, and that is deliberate rather than an omission.
# `gates/gates-pop.py` clause I DISCOVERS gates by that AST node, so a census that carries one
# becomes a gate, lands in the ledger, and turns the meta-gate red for the crime of being a
# census. `gates/opseven-oracle.py` has no guard either, and that is the house shape for an
# oracle. Run this file BY PATH; `raise SystemExit` at top level keeps the exit status.
raise SystemExit(main())
