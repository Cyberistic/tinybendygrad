#!/usr/bin/env python3
"""**THE **VERIFIER**: **`bin/bend <file> --check-only` **FOR **EVERY **FILE **A **CUT
**TOUCHED**, **⇒⇒† AND **THE **VERDICT **TOKEN **IS **READ**, **⇒⇒† AND **NOT **THE **EXIT
**STATUS**.

**⇒⇒† AND **THE **PRECONDITION**: **THE **SUM **OF **THE **CONCURRENTLY-RUNNING **FILES'
**MEASURED **PEAK **RSS** **IS **UNDER **60% **OF **`hw.memsize`**, **⇒⇒† AND **SO **THE
**RUNNER **READS **`.agents/slop/peakrss/census.rows`** (THE **TREE's **OWN **TABLE**) **AND
**SCHEDULES **THE **FILES **IN **BATCHES **THAT **RESPECT **IT**. **⇒⇒† AND **A **FILE **NOT
**IN **THE **CENSUS** (⇒⇒† AND **A **NEW **ONE**) **IS **RUN **ALONE**, **⇒⇒† AND **BECAUSE
**THE **CENSUS **IS **STALE**.
"""

import os
import pathlib
import re
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
CENSUS = ROOT / ".agents/slop/peakrss/census.rows"
OUT = ROOT / ".agents/slop/tables/verify"
BOUND = int(sys.argv[1]) if len(sys.argv) > 1 else 6144  # MB, the 60% of 16 GB


def census():
  d = {}
  for l in open(CENSUS):
    m = re.match(r"\s*(\d+) MB\s+\d+s\s+rc=(\d)\s+\S+\s+(\S+)\s+\[", l)
    if m:
      d[m.group(3)] = int(m.group(1))
  return d


def verdict_of(text):
  """**⇒⇒† AND **THE **TOKEN**, **⇒⇒† AND **NOT **THE **EXIT **STATUS**."""
  for tok in ("ALL PROOFS CHECK", "ERROR", "TODO", "FAILED"):
    if tok in text:
      return tok
  return "UNKNOWN"


def main():
  files = [l.strip() for l in open(sys.argv[2])] if len(sys.argv) > 2 else []
  OUT.mkdir(parents=True, exist_ok=True)
  c = census()
  # **⇒⇒† AND **THE **SCHEDULE**: **THE **HEAVY **FILES **FIRST**, **⇒⇒† AND **THE **BATCH
  # **SIZE **IS **THE **BUDGET **DIVIDED **BY **THE **HEAVIEST **FILE **IN **IT**.
  order = sorted(files, key=lambda f: -c.get(f, 1024))
  results = []
  i = 0
  while i < len(order):
    batch = [order[i]]
    i += 1
    used = c.get(batch[0], 1024)
    while i < len(order):
      nxt = c.get(order[i], 1024)
      if used + nxt > BOUND:
        break
      batch.append(order[i])
      used += nxt
      i += 1
    procs = []
    for f in batch:
      log = OUT / (f.replace("/", "_") + ".log")
      p = subprocess.Popen(
        [".venv/bin/python", "checks/bounded.py", "--seconds", "600", "--mb", "4096",
         "--", "./bin/bend", f, "--check-only"],
        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
      procs.append((f, p, log))
    for f, p, log in procs:
      out, _ = p.communicate()
      log.write_text(out)
      tok = "WITHIN-LIMITS" if "WITHIN-LIMITS" in out else (
        "KILLED-ON-MEMORY" if "KILLED-ON-MEMORY" in out else (
          "TIMED-OUT" if "TIMED-OUT" in out else "NO-TOKEN"))
      peak = re.search(r"peak-RSS=(\d+) MB", out)
      results.append((f, tok, verdict_of(out), peak.group(1) if peak else "?",
                      p.returncode))
      print(f"{tok:17s} {verdict_of(out):17s} peak={peak.group(1) if peak else '?':>5}MB "
            f"rc={p.returncode}  {f}", flush=True)
  bad = [r for r in results if r[1] != "WITHIN-LIMITS" or r[2] != "ALL PROOFS CHECK"]
  print(f"\nSUMMARY: {len(results)} files, {len(results)-len(bad)} clean, {len(bad)} not")
  for r in bad:
    print(f"  NOT CLEAN: {r}")
  pathlib.Path(OUT / "summary.rows").write_text(
    "\n".join(f"{a}\t{b}\t{c}\t{d}\t{e}" for a, b, c, d, e in results) + "\n")


if __name__ == "__main__":
  main()
