#!/usr/bin/env python3
"""**THE **BASELINE **TREE **FOR **THE **WGSL **A/B**: **A **COPY **OF **THE **PORT **WITH **EVERY
**TOUCHED **FILE **PUT **BACK **TO **`HEAD`**, **AND **A **COPY **OF **THE **BROWSER's **DRIVERS
**POINTING **AT **IT.**

**WHY.** THE BASELINE HAS TO BE **A **DIFFERENT **TREE**: THE PORT's **TYPES **ARE **NOMINAL** (⇒⇒†
AND **AND **A **`List<&2, C.KU>` **FROM **ONE **COPY **OF **`cstyle.bend`** **IS **NOT **A
**`List<&2, C.KU>` **FROM **ANOTHER**), **⇒⇒† AND **SO **THE **BASELINE's **BROWSER **DRIVERS
**MUST **IMPORT **THE **BASELINE's **PORT**).

**⇒⇒† AND **AND **THE **REPLACEMENT **MUST **BE **THE **ONE **THE **DRIVER **WRITES**: **A
**REPLACEMENT **THAT **MATCHES **NOTHING **LEAVES **THE **BASELINE **AS **THE **TREE **AGAIN**, **⇒⇒†
**AND **AND **THE **TWO **BUILDS **THEN **DIFFER **IN **NOTHING **AND **THE **A/B **IS **A
**COMPARISON **OF **A **THING **WITH **ITSELF** (⇒⇒† AND **AND **THAT **IS **A **BUG **THIS
**FILE **WAS **WRITTEN **TO **PREVENT**)**.
"""

import pathlib
import shutil
import subprocess

R = pathlib.Path(__file__).resolve().parents[3]
HERE = R / ".agents" / "slop" / "wgslperf"
BEND = R / "bin/bend"

# **⇒⇒† AND **THE **PORT's **PATH **AS **THE **DRIVERS **WRITE **IT.**
PORT = "./../../../tinybendygrad/"


def touched():
  """**THE **FILES **THE **WORKING **TREE **TOUCHED**, **AND **THEIR **HEAD **VERSIONS**."""
  out = subprocess.run(["git", "diff", "--name-only", "HEAD"], capture_output=True, text=True,
                       cwd=str(R)).stdout.split()
  return [f for f in out if f.startswith("tinybendygrad/")]


def build_base():
  """**THE **BASELINE **TREE**, **THE **BASELINE **BROWSER**, **AND **THE **BASELINE **DRIVER**."""
  base_root = HERE / "baseline-tree"
  if base_root.exists():
    shutil.rmtree(base_root)
  shutil.copytree(R / "tinybendygrad", base_root)
  for f in touched():
    rel = f[len("tinybendygrad/"):]
    (base_root / rel).write_text(subprocess.run(["git", "show", f"HEAD:{f}"], capture_output=True,
                                                text=True, cwd=str(R)).stdout)
  browser_root = HERE / "baseline-browser"
  if browser_root.exists():
    shutil.rmtree(browser_root)
  shutil.copytree(R / ".agents" / "slop" / "browser", browser_root)
  for b in browser_root.glob("*.bend"):
    text = b.read_text()
    if PORT in text:
      b.write_text(text.replace(PORT, "../baseline-tree/"))
  driver = (HERE / "wgslprof.bend").read_text()
  driver = driver.replace(PORT, "./baseline-tree/").replace("../browser/", "./baseline-browser/")
  if PORT in driver or "../browser/" in driver:
    raise SystemExit("WARN: the baseline driver's replacement did not take -- the A/B WOULD "
                     "COMPARE THE TREE WITH ITSELF")
  base_driver = HERE / "wgslprof.base.bend"
  base_driver.write_text(driver)
  return base_driver


def build(driver: pathlib.Path, out: pathlib.Path):
  b = subprocess.run([str(BEND), str(driver), "-o", str(out)], capture_output=True, text=True)
  if b.returncode != 0 or not out.exists():
    raise SystemExit(f"WARN: {driver.name} did not build:\n{b.stderr[:1500]}")
