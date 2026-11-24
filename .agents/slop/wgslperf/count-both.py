#!/usr/bin/env python3
"""**THE **CALL **COUNTS **OF **TWO **COMPILED **BUILDS**, **SIDE **BY **SIDE** -- **⇒⇒† AND **AND **THE
**COUNTS **ARE **THE **NOISE-FREE **READING** (⇒⇒† AND **AND **THE **TREE's OWN **RULE**: **THE **COUNT **IS
**THE **MULTIPLIER**, **⇒⇒† AND **AND **AND **THE **MACHINE **IS **LOADED**, **⇒⇒† AND **AND **AND **AN
**ABSOLUTE **TIME **IS **A **READING **OF **THE **LOAD**)**.

**⇒⇒† AND **THE **COUNTERS **ARE **PUT **IN **BOTH **BUILDS **THE **SAME **WAY** (⇒⇒† AND **AND **THE
**SITES **ARE **MATCHED **BY **THEIR **COMPILED **NAMES**, **⇒⇒† AND **AND **AND **A **SITE **THAT **IS **NOT
**IN **ONE **BUILD **IS **REPORTED **AS **ABSENT**, **⇒⇒† AND **AND **AND **NOT **AS **ZERO**)**
"""

import json
import pathlib
import re
import subprocess
import sys

R = pathlib.Path(__file__).resolve().parents[3]
HERE = R / ".agents/slop/wgslperf"

ACC = ('globalThis.__C = globalThis.__C || {};\n'
       'globalThis.__CC = (k) => { globalThis.__C[k] = (globalThis.__C[k] || 0) + 1; };\n')

# **⇒⇒† AND **THE **SITES**, **BY **THEIR **COMPILED **NAME's **TAIL** (⇒⇒† AND **AND **THE **TAIL **MUST
# **BE **UNIQUE **IN **THE **BUILD**, **⇒⇒† AND **AND **AND **A **DUPLICATE **IS **REPORTED**)**
SITES = [
  "Kahn_get_step", "Kahn_get_go", "Kahn_step", "Kahn_run", "Table_put", "Kahn_go",
  "uop_fold_folded", "wk_once", "wk_scan", "wk_try", "wk_fix_go", "wk_fix_fold",
  "wk_cast_body", "wk_cast_consts", "pm_claimed", "pm_early",
]


def instrument(src: str, tag: str) -> pathlib.Path:
  out = HERE / f"count-{tag}.mjs"
  names = {}
  for tail in SITES:
    ms = sorted(set(re.findall(r"function (\$[A-Za-z0-9_]*" + re.escape(tail) + r")\(", src)))
    if len(ms) != 1:
      print(f"  (the {tail} matched {len(ms)} -- SKIPPED)")
      continue
    names[tail] = ms[0]
  s = src
  # **⇒⇒† AND **THE **COUNTER **IS **AT **THE **ENTRY** (⇒⇒† AND **AND **PARENTHESIZED** (⇒⇒† AND **AND
  # **AN **UNPARENTHESIZED **COUNTER **AT **A **CALL **SITE **BECOMES **AN **EXTRA **ARGUMENT**))**
  for tail, fname in names.items():
    m = re.search(r"(function " + re.escape(fname) + r"\([^)]*\)\s*\{)", s)
    if not m:
      continue
    s = s[:m.end()] + f' globalThis.__CC("{tail}");' + s[m.end():]
  # **⇒⇒† AND **THE **ACCUMULATOR **AND **THE **DUMP**
  i = s.find("function $chain_wgsl(")
  if i < 0:
    raise SystemExit("WARN: no chain_wgsl")
  s = s[:i] + ACC + s[i:]
  out.write_text(s)
  return out


def run(js: pathlib.Path, tag: str):
  call = HERE / f"count-call-{tag}.mjs"
  call.write_text(f'import M from "./{js.name}";\n'
                  f'import fs from "fs";\n'
                  f'M["chain_wgsl"]();\n'
                  f'fs.writeFileSync("/tmp/wgslcount-{tag}.json", JSON.stringify(globalThis.__C || {{}}));\n')
  r = subprocess.run(["node", str(call)], capture_output=True, text=True)
  if r.returncode != 0:
    raise SystemExit(f"WARN: the driver did not run:\n{r.stderr[:1200]}")
  return json.loads(pathlib.Path(f"/tmp/wgslcount-{tag}.json").read_text())


def main():
  a = instrument(pathlib.Path(sys.argv[1]).read_text(), "a")
  b = instrument(pathlib.Path(sys.argv[2]).read_text(), "b")
  A = run(a, "a")
  B = run(b, "b")
  print()
  print(f"  {'SITE':22s} {'A (the baseline)':>18s} {'B (the change)':>16s} {'RATIO':>10s}")
  for k in sorted(set(A) | set(B)):
    a, b = A.get(k, 0), B.get(k, 0)
    ratio = f"{b/a:.4f}" if a else ("--" if b == 0 else "A=0")
    print(f"  {k:22s} {a:18,} {b:16,} {ratio:>10s}")


if __name__ == "__main__":
  main()
