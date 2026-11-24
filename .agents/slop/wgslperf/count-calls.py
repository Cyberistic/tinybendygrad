#!/usr/bin/env python3
"""**THE **CALL **COUNTS **OF **THE **HOT **FUNCTIONS**, **MEASURED **IN **THE **COMPILED **JS** -- **⇒⇒† AND
**AND **THE **COUNTS **ARE **WHAT **SHOW **A **QUADRATIC**.

**WHY.** THE **PROFILE** (`profile-wgsl.py`) **SAYS **WHERE **THE **TIME **IS**: **`wk_commit` **13.7 s**,
**`late_apply` **5.5 s**, **`kg()` **6.4 s** (⇒⇒† AND **AND **THE **WGSL **WALK **AND **RENDER **ARE
**3.3 ms** -- **⇒⇒† AND **SO **`wgsl.bend`'s **66 **`String.concat`** **CALLS **ARE **NOT **THE
**TARGET**) -- **⇒⇒† AND **AND **THE **NEXT **QUESTION **IS **HOW **MANY **TIMES **THE **INNER **WORK
**RUNS**.

**⇒⇒† AND **THE **COUNT **AT **A **CALL **SITE** (⇒⇒† AND **AND **THE **COUNTER **IS **PARENTHESIZED**,
**⇒⇒† AND **AND **THE **TREE's OWN **RULE**) **AND **THE **COUNTS **ARE **FOR **THE **HOT **FUNCTIONS**:
**`F.folded`** (⇒⇒† AND **THE **WHOLE-ARENA **FOLD**), **`UOp.fold`**, **`Kahn.run`**, **`wk_once`**,
**`wk_scan`**, **`wk_try`**, **`O.pm_claimed`**, **`O.pm_early`**, **`late_apply`**, **`kg`**.
"""

import json
import pathlib
import re
import subprocess
import sys
import time

R = pathlib.Path(__file__).resolve().parents[3]
HERE = R / ".agents/slop/wgslperf"
BEND = R / "bin/bend"

ACC = """globalThis.__C = globalThis.__C || {};
globalThis.__CC = (k) => { globalThis.__C[k] = (globalThis.__C[k] || 0) + 1; };"""


def find_fn(src: str, name: str):
  i = src.find(f"function {name}(")
  if i < 0:
    return None, None
  j = src.index("{", i)
  depth = 0
  k = j
  while k < len(src):
    ch = src[k]
    if ch == '"':
      k += 1
      while k < len(src):
        if src[k] == "\\":
          k += 2
          continue
        if src[k] == '"':
          break
        k += 1
    elif ch == "{":
      depth += 1
    elif ch == "}":
      depth -= 1
      if depth == 0:
        rest = src[k + 1:k + 12].lstrip()
        if rest.startswith("else"):
          k += 1
          continue
        return i, k + 1
    k += 1
  return i, None


def main():
  base = HERE / "wgslprof.mjs"
  if not base.exists():
    b = subprocess.run([str(BEND), str(HERE / "wgslprof.bend"), "-o", str(base)],
                       capture_output=True, text=True)
    if b.returncode != 0:
      raise SystemExit(f"WARN: the driver did not build:\n{b.stderr[:1200]}")
  src = base.read_text()

  # **⇒⇒† AND **THE **FUNCTIONS **TO **COUNT** (⇒⇒† AND **AND **THE **NAMES **ARE **READ **OUT **OF
  # **THE **COMPILED **FORM**)**
  NAMES = [
    "folded", "UOp.fold", "Kahn.run", "wk_once", "wk_scan", "wk_try",
    "pm_claimed", "pm_early", "late_apply", "kg", "wk_fix.go", "wk_sweep.go",
    "body_kus", "wk_commit",
    # **⇒⇒† AND **THE **FOLD's **OWN **WORK** (⇒⇒† AND **AND **THE **TREE's OWN **LESSON**: **THE
    # **COUNT **IS **THE **MULTIPLIER**)**
    "uop_fold_Kahn_seed", "uop_fold_Kahn_step", "uop_fold_Kahn_run", "uop_fold_UOp_fold",
    "uop_fold_Kahn_seed_work", "uop_fold_Kahn_seed_pend",
    # **⇒⇒† AND **THE **ENGINE's **OWNS **FOLDS** (⇒⇒† AND **AND **THE **SEVEN **STAGES' **FIXPOINTS**)
    "uop_fold_folded", "eng_fix_go", "eng_apply",
    "eng_run_stages",
    # **⇒⇒† AND **THE **FIRINGS** (⇒⇒† AND **AND **THE **FOLD **IS **REBUILT **ON **A **FIRING**,
    # **⇒⇒† AND **AND **THE **FIRING **COUNT **IS **THE **FOLD **COUNT **THE **FIX **MUST **CUT**)**
    "uop_weak_wk_fix_fold", "wk_fix_fold", "wk_fix_go", "uop_weak_wk_cast_body", "uop_weak_wk_remint_cast",
    "uop_weak_wk_commit_dispatch_go", "uop_weak_wk_cast_consts",
    "uop_weak_wk_norm", "uop_weak_wk_has", "uop_weak_wk_last",
    "uop_ops_Arena_next",
    # **⇒⇒† AND **THE **TABLE's **TWO **COSTS** (⇒⇒† AND **AND **THE **PUT **COPIES **THE **LIST **AND
    # **THE **GET **SCANS **IT**)**
    "uop_fold_Table_put", "uop_fold_Kahn_get_go", "uop_fold_Kahn_get_step",
    "uop_fold_Kahn_pop_of", "uop_fold_Kahn_go",
  ]
  out = src
  found = []
  for key in NAMES:
    # **⇒⇒† AND **THE **NAME **IS **MATCHED **BY **ITS **TAIL** (⇒⇒† AND **AND **THE **PREFIX **IS
    # **THE **PORT's **MODULE **PATH**, **⇒⇒† AND **AND **THE **TAIL **IS **UNIQUE**)**
    pat = re.compile(r"function (\$[A-Za-z0-9_]*" + re.escape(key.split(".")[-1]) + r")\(")
    ms = pat.findall(out)
    # **⇒⇒† AND **THE **MATCH **MUST **BE **UNIQUE** (⇒⇒† AND **AND **A **DUPLICATE **MEANS **THE **NAME
    # **IS **AMBIGUOUS** **⇒⇒† AND **AND **THEN **IT **IS **SKIPPED **RATHER **THAN **COUNTED **WRONG**)**
    if len(ms) != 1:
      print(f"  (the {key} name matched {len(ms)} functions -- SKIPPED, an ambiguous name is not a count)")
      continue
    fname = ms[0]
    i, end = find_fn(out, fname)
    body = out[i:end]
    # **⇒⇒† AND **THE **COUNTER **IS **AT **THE **ENTRY** (⇒⇒† AND **AND **IT **IS **PARENTHESIZED**)
    body = body.replace("{", "{\n  globalThis.__CC(\"" + key + "\");", 1)
    out = out[:i] + body + out[end:]
    found.append(key)
  print(f"THE COUNTED FUNCTIONS: {len(found)}  ({', '.join(found)})")

  # **⇒⇒† AND **THE **ACCUMULATOR**, **AND **THE **DUMP**
  m = re.search(r"function (\$chain_wgsl)\(([^)]*)\)\s*\{", out)
  if not m:
    raise SystemExit("WARN: no chain_wgsl")
  i = out.find(m.group(0))
  out = out[:i] + ACC + out[i:]

  call = HERE / "call-count.mjs"
  call.write_text('import M from "./wgslprof.count.mjs";\n'
                  'import fs from "fs";\n'
                  'M["chain_wgsl"]();\n'
                  'fs.writeFileSync(process.env.__WGSL_OUT || "/tmp/wgslcount.json",\n'
                  '  JSON.stringify(globalThis.__C || {}));\n')
  outp = HERE / "wgslprof.count.mjs"
  outp.write_text(out)

  env = dict(subprocess.os.environ)
  env["__WGSL_OUT"] = "/tmp/wgslcount.json"
  t0 = time.perf_counter()
  b = subprocess.run(["node", str(call)], capture_output=True, text=True, env=env)
  wall = (time.perf_counter() - t0) * 1000
  if b.returncode != 0:
    print(b.stderr[:1200])
    raise SystemExit("WARN: the counting driver did not run")
  print(f"THE WHOLE: {wall:.1f} ms")
  try:
    C = json.loads(pathlib.Path("/tmp/wgslcount.json").read_text())
  except Exception as e:
    print("WARN: no dump:", e)
    return
  # **⇒⇒† AND **THE **ARENA's **GROWTH** (⇒⇒† AND **AND **THE **FOLD **IS **A **WHOLE-ARENA
  # **TOPOLOGICAL **SORT**, **⇒⇒† AND **AND **SO **THE **FOLD's **COST **IS **THE **ARENA's **SIZE**)**.
  print()
  print("THE **ARENA's **SIZE** (⇒⇒† AND **AND **THE **FOLD **SORTS **THE **WHOLE **ARENA**):")
  for k in sorted(C):
    if "Arena_next" in k or "arena_next" in k:
      print(f"  {k:24s} {C[k]/60:12,.0f} a turn")
  print()
  print("THE CALL COUNTS:")
  for k, v in sorted(C.items(), key=lambda kv: -kv[1]):
    print(f"  {k:16s} {v:12,}")
  # **⇒⇒† AND **THE **SCAN's **CELL **VISITS **ARE **THE **AMOUNT **AN **O(1) **LOOKUP **REMOVES** (⇒⇒† AND
  # **AND **AND **THE **COUNT **IS **THE **MULTIPLIER**)**
  step = C.get("uop_fold_Kahn_get_step", 0)
  go = C.get("uop_fold_Kahn_get_go", 0)
  if step:
    print()
    print(f"  THE SCAN's CELL VISITS: {step:,}  (over {go:,} scans)")
    print(f"  **⇒⇒† AND **AN **O(1) **LOOKUP **REMOVES **ALL **OF **THEM**")


if __name__ == "__main__":
  main()
