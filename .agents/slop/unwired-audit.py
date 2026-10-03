#!/usr/bin/env python3
"""unwired-audit.py -- the AUDIT half: for every target port BASE_ORACLES does NOT wire, what
would it take to wire it?

Three questions per port, and each is answered by a MEASUREMENT, not by a name:

  1 DOES IT PRINT ROWS AT ALL.  A port whose lane emits no `name=value` cannot share a row
    name with anything, so no oracle can ever be non-empty for it. `helpers.bend` is the
    known instance and the claim deserves to be measured rather than repeated.

  2 DOES ANY ORACLE ON DISK ALREADY SHARE A ROW NAME WITH IT.  Read out of
    /tmp/rebase-scan/o_*.json -- oracles that have ALREADY been run, so nothing is re-executed
    and a fresh sweep cannot produce a fresh, different answer. A pair with shared>0 and
    dis=0 is wireable TODAY.

  3 WHICH ORACLE FILES NAME THIS PORT.  A filename match is weak evidence, so it is reported
    as a LEAD with the measured answer beside it, never as the answer: `elf_rows.py` and
    `sqtt_spec.py` have no "oracle" or "gate" in the name and so were structurally invisible
    to rebase-scan-oracles.py's candidate filter, and both are wired and working.

  usage: .venv/bin/python .agents/slop/unwired-audit.py
"""
import concurrent.futures as cf
import importlib.util
import json
import os
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
SCAN = pathlib.Path("/tmp/rebase-scan")


def load(path, name):
  spec = importlib.util.spec_from_file_location(name, str(path))
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


def targets():
  return [l.strip() for l in (HERE / "rebase" / "targets.txt").read_text().splitlines()
          if l.strip()]


def wired():
  """The wired roster, read from the GATE AS A MODULE. Not parsed out of the text with a
  regex: a regex over the source is how a roster can look right while the tool reads a
  different one."""
  return load(HERE / "rebase-gate.py", "unwired_audit_gate").BASE_ORACLES


def cached_oracles():
  """{spec_key: {name: value}} for every oracle lane already run, from the scan cache."""
  out = {}
  for f in SCAN.glob("o_*.json"):
    try:
      d = json.loads(f.read_text())
    except ValueError:
      print(f"  ({f} is not readable JSON; skipped rather than counted as an empty lane)")
      continue
    if d:
      out[f.stem[2:]] = d
  return out


def oracle_files_naming(stems):
  """SLOP-AUTHORED .py files whose NAME contains a port's stem. A LEAD, not a measurement.

  ⚠ SCOPED TO SLOP-AUTHORED FILES, and the scoping is a fix, not a filter. The first
  version of this walked `HERE.rglob("*.py")`, which descended into `.agents/slop/xd1/` --
  four whole tinygrad CHECKOUTS that other units vendored for their own comparisons. Every
  `kernel.bend` therefore "had" sixteen oracle-shaped files, all of them tinygrad's own
  `kernel.py`/`weak.py`/`multi.py`, and the report said so. A lead list made of another
  repository's source files is not a lead list; it is a directory listing. `xd1`, `xd2`,
  `opstree`, `work`, `head`, `pin`, `cur` and `probe` are excluded by name."""
  VENDORED = {"xd1", "xd2", "opstree", "work", "head", "pin", "cur", "probe", "elf", "nir",
              "ind", "nr", "nl", "vz", "tcptx", "hdrbase", "runs", "plans", "oracle"}
  files = [p for p in HERE.rglob("*.py")
           if not (set(p.relative_to(HERE).parts) & VENDORED)
           and "rebase-" not in p.name and "rebase_" not in p.name]
  found = {s: [] for s in stems}
  for p in sorted(files):
    parts = set(re.split(r"[^A-Za-z0-9]+", p.stem))
    for s in stems:
      # The stem's own words, so `multi-rows.py` leads to `multi.bend` but `mt_seam_rows.py`
      # does not lead to `render.bend` on the strength of the word "render" appearing
      # somewhere in a vendored tree.
      if set(s.split("_")) & parts:
        found[s].append(str(p.relative_to(REPO)))
  return found


def main():
  gate_wired = wired()
  all_targets = targets()
  unwired = [p for p in all_targets if p not in gate_wired]
  on_disk = [p for p in unwired if (REPO / p).exists()]
  print(f"{len(all_targets)} targets, {len(gate_wired)} wired in BASE_ORACLES, "
        f"{len(unwired)} unwired ({len(on_disk)} exist on disk)\n")

  scan = load(HERE / "rebase-scan-oracles.py", "unwired_audit_scan")
  print("MEASURING each unwired port's own lane (real ./bin/bend run, cached):")
  with cf.ThreadPoolExecutor(max_workers=8) as pool:
    rows = dict(zip(on_disk, pool.map(scan.bend_rows, on_disk)))
  for p in on_disk:
    print(f"  {len(rows[p]):>5} rows  {p}")

  oracles = cached_oracles()
  print(f"\n{len(oracles)} cached oracle row-sets in {SCAN} (nothing re-run)\n")
  print(f"{'shared':>6} {'dis':>5}  {'port':<40} oracle")
  hits = []
  for p in on_disk:
    b = rows[p]
    if not b:
      continue
    for key, o in oracles.items():
      shared = set(o) & set(b)
      if shared:
        hits.append((len(shared), sum(1 for k in shared if o[k] != b[k]), p, key))
  hits.sort(reverse=True)
  for n, d, p, key in hits:
    print(f"{n:>6} {d:>5}  {p:<40} {key}")
  if not hits:
    print("  (none: no cached oracle shares a single row name with any unwired port)")

  print("\nSLOP files whose NAME contains the port's stem -- LEADS ONLY, not measurements:")
  stems = {pathlib.Path(p).stem: p for p in unwired}
  for stem, files in oracle_files_naming(stems).items():
    p = stems[stem]
    print(f"  {p}")
    for f in files or ["  (none)"]:
      print(f"      {f}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
