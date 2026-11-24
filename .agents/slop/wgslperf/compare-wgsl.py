#!/usr/bin/env python3
"""**THE **WGSL **BYTES**, **BEFORE **AND **AFTER **A **CHANGE** -- **⇒⇒† AND **AND **THE **WGSL **MUST **BE
**THE **SAME **STRING**, **⇒⇒† AND **AND **A **SHORTER **ONE **IS **A **CORRECTNESS **DEFECT** **AND **NOT
**A **WIN**.

**⇒⇒† AND **THE **COMPARISON **IS **OVER **THE **DRIVER's **OWN **OUTPUT** (⇒⇒† AND **AND **THE **DRIVER
**IS **A **COPY **OF **THE **ORIGINAL **`.agents/slop/browser/fchainwgsl.bend`**)**, **⇒⇒† AND **AND **BOTH
**BUILDS **ARE **MADE **NOW** (⇒⇒† AND **AND **A **STALE **BUILD **IS **A **SECOND **SOURCE **OF
**TRUTH**)**.
"""

import pathlib
import subprocess
import sys

R = pathlib.Path(__file__).resolve().parents[3]
HERE = R / ".agents/slop/wgslperf"
BEND = R / "bin/bend"


def build(driver: pathlib.Path, out: pathlib.Path) -> pathlib.Path:
  b = subprocess.run([str(BEND), str(driver), "-o", str(out)], capture_output=True, text=True)
  if b.returncode != 0 or not out.exists():
    raise SystemExit(f"WARN: {driver.name} did not build:\n{b.stderr[:1200]}")
  return out


def run(js: pathlib.Path, tag: str) -> str:
  call = HERE / f"call-{tag}.mjs"
  call.write_text(f'import M from "./{js.name}";\n'
                  f'process.stdout.write(M["chain_wgsl"]());\n')
  b = subprocess.run(["node", str(call)], capture_output=True, text=True)
  if b.returncode != 0:
    raise SystemExit(f"WARN: the driver did not run:\n{b.stderr[:1200]}")
  return b.stdout


def main():
  new = build(HERE / "wgslprof.bend", HERE / "wgslprof.new.mjs")
  # **⇒⇒† AND **THE **BASELINE **IS **THE **COMMITTED **`weak.bend`** (⇒⇒† AND **AND **THE **CHANGE **IS
  # **IN **THE **WORKING **TREE**) -- **⇒⇒† AND **AND **THE **BASELINE **DRIVER **IS **THE **SAME **FILE
  # **WITH **THE **COMMITTED **`weak.bend`** **PUT **BACK** (⇒⇒† AND **AND **THE **DRIVER **IS **A **COPY**,
  # **⇒⇒† AND **AND **THE **COPY **IS **WHAT **IS **BUILT**)**
  base_tree = HERE / "baseline"
  base_tree.mkdir(exist_ok=True)
  committed = subprocess.run(["git", "show", "HEAD:tinybendygrad/uop/weak.bend"],
                             capture_output=True, text=True, cwd=str(R)).stdout
  if not committed:
    raise SystemExit("WARN: the committed weak.bend is not readable")
  (base_tree / "weak.bend").write_text(committed)
  # **⇒⇒† AND **THE **BASELINE **DRIVER **IS **THE **SAME **DRIVER **WITH **THE **IMPORT **POINTING **AT **THE
  # **COMMITTED **`weak.bend`** -- **⇒⇒† AND **AND **THAT **IS **A **COPY **OF **THE **TREE's **`tinybendygrad`
  # **WITH **ONE **FILE **SWAPPED** (⇒⇒† AND **AND **SO **THE **REST **IS **THE **SAME **TREE**)**
  base_root = HERE / "baseline-tree"
  if base_root.exists():
    subprocess.run(["rm", "-rf", str(base_root)], check=True)
  subprocess.run(["cp", "-R", str(R / "tinybendygrad"), str(base_root)], check=True)
  (base_root / "uop/weak.bend").write_text(committed)
  driver = (HERE / "wgslprof.bend").read_text()
  driver = driver.replace("../../../../tinybendygrad/", "../../baseline-tree/")
  (HERE / "wgslprof.base.bend").write_text(driver)
  # **⇒⇒† AND **THE **BROWSER **FILES **ARE **THE **PORT's **OWN** (⇒⇒† AND **AND **THE **DRIVER **IMPORTS
  # **`.agents/slop/browser/ku2r.bend`**, **⇒⇒† AND **AND **THE **PATH **IS **RELATIVE **TO **THE
  # **DRIVER**, **⇒⇒† AND **AND **SO **THE **DRIVER **STAYS **WHERE **IT **IS**)**.
  base = build(HERE / "wgslprof.base.bend", HERE / "wgslprof.base.mjs")
  wb = run(base, "base")
  wn = run(new, "new")
  print()
  print("THE **WGSL**:")
  print("  the baseline: %d bytes" % len(wb))
  print("  the change:   %d bytes" % len(wn))
  if wb == wn:
    print("  **THE **WGSL **IS **BYTE-IDENTICAL**")
  else:
    print("  **THE **WGSL **DIFFERS** -- and a SHORTER one is a CORRECTNESS DEFECT")
    for i, (x, y) in enumerate(zip(wb, wn)):
      if x != y:
        print("  the first difference at %d:" % i)
        print("    A: %r" % wb[max(0, i - 100):i + 100])
        print("    B: %r" % wn[max(0, i - 100):i + 100])
        break
    else:
        print("  the shorter one ends at %d" % min(len(wb), len(wn)))
        print("    A's tail: %r" % wb[min(len(wb), len(wn)):][:200])
        print("    B's tail: %r" % wn[min(len(wb), len(wn)):][:200])


if __name__ == "__main__":
  main()
