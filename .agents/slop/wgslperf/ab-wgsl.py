#!/usr/bin/env python3
"""**THE **WGSL **GENERATION's **A/B**, **PAIRED**, **BETWEEN **TWO **BUILDS** -- **⇒⇒† AND **AND **THE
**MACHINE **IS **LOADED**, **⇒⇒† AND **AND **SO **THE **VERDICT **IS **THE **RATIO **OF **THE **PAIRED
**RUNS**, **⇒⇒† AND **AND **NOT **AN **ABSOLUTE **TIME** (⇒⇒† AND **AND **THE **TREE's OWN **RULE**)**.

**⇒⇒† AND **THE **RUNS **ARE **ALTERNATED** (⇒⇒† AND **AND **AND **THE **SAME **BUILD **AGAINST
**ITSELF **IS **A **THIRD **ARM**, **⇒⇒† AND **AND **SO **THE **NOISE **IS **READ **AT **THE **SAME
**MOMENT**)**
"""

import json
import pathlib
import statistics
import subprocess
import sys
import time

R = pathlib.Path(__file__).resolve().parents[3]
HERE = R / ".agents/slop/wgslperf"


def build(driver: pathlib.Path, out: pathlib.Path):
  b = subprocess.run([str(R / "bin/bend"), str(driver), "-o", str(out)], capture_output=True, text=True)
  if b.returncode != 0 or not out.exists():
    raise SystemExit(f"WARN: {driver} did not build:\n{b.stderr[:1200]}")
  return out


def runner(js: pathlib.Path, tag: str) -> pathlib.Path:
  p = HERE / f"run-{tag}.mjs"
  p.write_text(f'import M from "./{js.name}";\n'
               f'const t0 = Date.now();\n'
               f'const w = M["chain_wgsl"]();\n'
               f'console.log(JSON.stringify({{ms: Date.now() - t0, bytes: w.length, w}}));\n')
  return p


def one(p: pathlib.Path):
  r = subprocess.run(["node", str(p)], capture_output=True, text=True)
  if r.returncode != 0:
    raise SystemExit(f"WARN: the driver did not run:\n{r.stderr[:1200]}")
  return json.loads(r.stdout.strip().splitlines()[-1])


def main():
  # **⇒⇒† AND **THE **THREE **BUILDS**: **A **AND **B **ARE **THE **TWO **SIDES**, **AND **C **IS **THE
  # **SAME **BUILD **AS **A** (⇒⇒† AND **AND **SO **THE **NOISE **IS **READ **AT **THE **SAME **MOMENT**)**
  # **⇒⇒† AND **THE **TWO **SIDES **ARE **TWO **DRIVERS** (⇒⇒† AND **AND **AND **THEY **MUST **BE **BUILT
  # **FROM **THEIR **OWN **TREES**, **⇒⇒† AND **AND **AND **SO **THE **CALLER **BUILDS **THEM **AND **PASSES
  # **THE **JS**)**
  a_js = pathlib.Path(sys.argv[1])
  b_js = pathlib.Path(sys.argv[2])
  c_js = pathlib.Path(sys.argv[3]) if len(sys.argv) > 4 else a_js
  pa, pb, pc = runner(a_js, "a"), runner(b_js, "b"), runner(c_js, "c")

  ta, tb, tc = [], [], []
  wa = wb = None
  for _ in range(int(sys.argv[3]) if len(sys.argv) > 3 else 5):
    ra = one(pa)
    rb = one(pb)
    rc = one(pc)
    ta.append(ra["ms"])
    tb.append(rb["ms"])
    tc.append(rc["ms"])
    wa, wb = ra["w"], rb["w"]
  print()
  print("THE **WGSL**:")
  print("  A: %d bytes   B: %d bytes   **%s**"
        % (len(wa), len(wb), "IDENTICAL" if wa == wb else "DIFFERENT"))
  if wa != wb:
    raise SystemExit("WARN: the WGSL differs -- a performance change that changes the output is a defect")
  print()
  print("THE **TIMES** (ms):")
  print("  A (the baseline): min %d  median %d" % (min(ta), statistics.median(ta)))
  print("  B (the change):   min %d  median %d" % (min(tb), statistics.median(tb)))
  print("  C (the noise floor, A against itself): min %d  median %d" % (min(tc), statistics.median(tc)))
  print()
  print("  THE RATIO OF THE MINIMA:  B/A %.4f   (the noise floor C/A %.4f)"
        % (min(tb) / min(ta), min(tc) / min(ta)))
  print("  THE RATIO OF THE MEDIANS: B/A %.4f   (the noise floor C/A %.4f)"
        % (statistics.median(tb) / statistics.median(ta),
           statistics.median(tc) / statistics.median(ta)))


if __name__ == "__main__":
  main()
