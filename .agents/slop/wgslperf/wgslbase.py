#!/usr/bin/env python3
"""**THE **BUNDLES **FOR **THE **WGSL **A/B**: **A **TREE **OF **THE **PORT**, **THE **BROWSER's
**DRIVERS **POINTING **AT **IT**, **AND **A **DRIVER **THAT **RUNS **THE **TURN.**

**WHY.** THE BASELINE HAS TO BE **A **DIFFERENT **TREE**: THE PORT's **TYPES **ARE **NOMINAL** (⇒⇒†
AND **AND **A **`List<&2, C.KU>` **FROM **ONE **COPY **OF **`cstyle.bend`** **IS **NOT **A
**`List<&2, C.KU>` **FROM **ANOTHER**), **⇒⇒† AND **SO **THE **BROWSER's **DRIVERS **MUST **IMPORT
**THE **SAME **TREE **THE **DRIVER **DOES**.

**⇒⇒† AND **AND **THE **REPLACEMENT **MUST **BE **THE **ONE **THE **DRIVER **WRITES**: **A
**REPLACEMENT **THAT **MATCHES **NOTHING **LEAVES **THE **BASELINE **AS **THE **TREE **AGAIN**, **⇒⇒†
**AND **AND **THE **TWO **BUILDS **THEN **DIFFER **IN **NOTHING **AND **THE **A/B **IS **A
**COMPARISON **OF **A **THING **WITH **ITSELF** (⇒⇒† AND **AND **THAT **IS **A **BUG **THIS
**FILE **WAS **WRITTEN **TO **PREVENT**)**.

**THE **LAYOUT.** **`<name>/tinybendygrad/`** (THE PORT), **`<name>/browser/`** (THE DRIVERS),
**`<name>/driver.bend`** (THE DRIVER). **THE **BUNDLE **IS **A **SCRATCH **COPY**: **IT **IS **WHERE
**A **CHANGE **IS **TESTED **BEFORE **IT **TOUCHES **THE **SHARED **TREE**.
"""

import pathlib
import shutil
import subprocess

R = pathlib.Path(__file__).resolve().parents[3]
HERE = R / ".agents" / "slop" / "wgslperf"
BEND = R / "bin/bend"

# **⇒⇒† AND **THE **PORT's **PATH **AS **THE **BROWSER's **DRIVERS **WRITE **IT.**
PORT = "./../../../tinybendygrad/"


def head_port(dirname: str, base: str = "HEAD") -> pathlib.Path:
  """**A **COPY **OF **THE **PORT **WITH **EVERY **FILE **THE **WORKING **TREE **TOUCHED **PUT
  **BACK **TO **THE **BASE **REVISION** -- **⇒⇒† AND **SO **THE **ONLY **DIFFERENCE **IS **THE
  **CHANGE **UNDER **TEST**."""
  dest = HERE / dirname / "tinybendygrad"
  if dest.exists():
    shutil.rmtree(dest)
  dest.parent.mkdir(parents=True, exist_ok=True)
  shutil.copytree(R / "tinybendygrad", dest)
  out = subprocess.run(["git", "diff", "--name-only", base], capture_output=True, text=True,
                       cwd=str(R)).stdout.split()
  for f in [f for f in out if f.startswith("tinybendygrad/")]:
    (dest / f[len("tinybendygrad/"):]).write_text(
      subprocess.run(["git", "show", f"{base}:{f}"], capture_output=True, text=True,
                     cwd=str(R)).stdout)
  return dest


def tree_port(dirname: str, fresh: bool = True) -> pathlib.Path:
  """**A **COPY **OF **THE **WORKING **TREE's **PORT** -- **⇒⇒† AND **AND **THIS **IS **WHERE **A
  **CHANGE **IS **TESTED **BEFORE **IT **TOUCHES **THE **SHARED **TREE**.

  **⇒⇒† AND **AND **`fresh=False` **LEAVES **AN **EXISTING **COPY **ALONE** (⇒⇒† AND **AND
  **RECREATING **IT **WOULD **WIPE **THE **EDIT **UNDER **TEST**)**."""
  dest = HERE / dirname / "tinybendygrad"
  if dest.exists():
    if not fresh:
      return dest
    shutil.rmtree(dest)
  dest.parent.mkdir(parents=True, exist_ok=True)
  shutil.copytree(R / "tinybendygrad", dest)
  return dest


def bundle(dirname: str, port: pathlib.Path) -> pathlib.Path:
  """**THE **BROWSER **AND **THE **DRIVER**, **POINTING **AT **THE **GIVEN **PORT**."""
  root = HERE / dirname
  browser = root / "browser"
  if browser.exists():
    shutil.rmtree(browser)
  shutil.copytree(R / ".agents" / "slop" / "browser", browser)
  for b in browser.glob("*.bend"):
    text = b.read_text()
    if PORT in text:
      b.write_text(text.replace(PORT, "../tinybendygrad/"))
  driver = (HERE / "wgslprof.bend").read_text()
  driver = driver.replace(PORT, "./tinybendygrad/").replace("../browser/", "./browser/")
  if PORT in driver or "../browser/" in driver:
    raise SystemExit("WARN: the driver's replacement did not take -- THE A/B WOULD COMPARE A THING "
                     "WITH ITSELF")
  out = root / "driver.bend"
  out.write_text(driver)
  return out


def build(driver: pathlib.Path, out: pathlib.Path):
  b = subprocess.run([str(BEND), str(driver), "-o", str(out)], capture_output=True, text=True)
  if b.returncode != 0 or not out.exists():
    raise SystemExit(f"WARN: {driver.name} did not build:\n{b.stderr[:1500]}")
