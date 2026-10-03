#!/usr/bin/env python3
"""wire-survey.py -- intersect ALREADY-RUN oracle row sets with the ports that have no
oracle wired, using rebase-scan-oracles.py's cache so nothing is re-run.

The point of reading the cache rather than re-running is arithmetic, not speed: a fresh sweep
re-measures oracles to answer a question whose answers are already on disk, and a
re-measurement is a chance to get a different answer. The cache is read as DATA and the
originating tool is named in the output, so the two measurements can be compared rather than
one of them taken on faith.

The default port list is derived from rebase-gate.py's BASE_ORACLES, not typed. The typed
list this replaced still named elf, sqtt, tc_ptx, generate and render after they were wired,
so a survey of "unwired" ports was surveying ports that had an oracle. A cache older than
the source is skipped: the tc_ptx cache from 14:33 still holds the six retired `py=` literals.

The "379" and "142" that used to sit in the paragraph above were a snapshot of one sweep.
They are not a control.

  usage: python3 .agents/slop/wire-survey.py [PORT ...]
"""
import json, os, pathlib, re, sys

from wire_parse import read_fresh_cache

REPO = pathlib.Path(__file__).resolve().parents[2]
SCAN = pathlib.Path("/tmp/rebase-scan")
BEND = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "rebase-wired-rows"


def unwired_ports():
  gate = (REPO / ".agents" / "slop" / "rebase-gate.py").read_text()
  i = gate.find("BASE_ORACLES = {")
  if i < 0:
    print("BASE_ORACLES not found in rebase-gate.py; refusing a typed unwired list",
          file=sys.stderr)
    return []
  j = gate.find("\n}\n", i)
  body = gate[i:j if j > i else None]
  wired = set(re.findall(r'^\s+"(tinybendygrad/[^"]+\.bend)":', body, re.M))
  if not wired:
    print("BASE_ORACLES parsed empty; refusing a typed unwired list", file=sys.stderr)
    return []
  return sorted(str(p.relative_to(REPO)) for p in (REPO / "tinybendygrad").rglob("*.bend")
                if str(p.relative_to(REPO)) not in wired)


def main():
  ports = sys.argv[1:] or unwired_ports()
  oracles = {}
  for f in SCAN.glob("o_*.json"):
    name = f.stem[2:]
    for s in f.read_text() and json.loads(f.read_text()).items():
      oracles.setdefault(name, {})[s[0]] = s[1]
  bend = {}
  for p in ports:
    cached, why = read_fresh_cache(BEND, p, REPO / p)
    if why == "stale":
      print(f"  ({p} cache is older than the source; not a reading)", file=sys.stderr)
      continue
    if cached is not None:
      bend[p] = cached
  print(f"{len(oracles)} cached oracle row-sets, {len(bend)}/{len(ports)} port row-sets\n")
  print(f"{'shared':>6} {'dis':>5}  {'port':<42} oracle")
  out = []
  for p, b in bend.items():
    for o, orows in oracles.items():
      shared = set(orows) & set(b)
      if not shared:
        continue
      dis = sum(1 for k in shared if orows[k] != b[k])
      out.append((len(shared), dis, p, o))
  out.sort(reverse=True)
  for n, d, p, o in out:
    print(f"{n:>6} {d:>5}  {p:<42} {o}")
  return 0


if __name__ == "__main__":
  sys.exit(main())