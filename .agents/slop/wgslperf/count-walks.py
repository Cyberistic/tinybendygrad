#!/usr/bin/env python3
"""**THE **COUNTS **OF **THE **WALKS, **MEASURED **IN **THE **COMPILED **FORM.**

**WHY.** THE PROFILE SAYS WHERE THE TIME IS, AND IT SAYS THE TIME IS SPREAD (⇒⇒† AND **THE **TOP
**TERM **IS **10%**), **⇒⇒† AND **AND **A **SPREAD **PROFILE **DOES **NOT **SAY **WHETHER **A
**WALK **IS **QUADRATIC** -- **AND **A **QUADRATIC **IS **A **DIFFERENT **KIND **OF **FIX** ✓.

**THE **COMMAND.** `.venv/bin/python .agents/slop/wgslperf/count-walks.py` -- **AND **IT **PRINTS
**THE **COUNT **OF **EVERY **WALK **AND **OF **THE **CALLS **THAT **MAKE **IT **QUADRATIC** ✓.

**THE **COUNTERS.**
  * `UOp.toposort` **CALLS** (⇒⇒† AND **EVERY **ONE **IS **A **WALK **OF **THE **ARENA**).
  * `Arena.budget` **CALLS** (⇒⇒† AND **EVERY **ONE **IS **A **FOLD **OVER **THE **ARENA**).
  * `List.contains` **CALLS** (⇒⇒† AND **EVERY **ONE **IS **A **LINEAR **SCAN **OF **A **LIST**).
  * `Arena.edges` **CALLS** (⇒⇒† AND **EVERY **ONE **IS **A **FOLD **OVER **EVERY **NODE**).
  * `Arena.at` **CALLS** (⇒⇒† AND **EVERY **ONE **IS **A **CHUNKED **LOOKUP**).
"""

import collections
import json
import pathlib
import re
import subprocess
import sys

R = pathlib.Path(__file__).resolve().parents[3]
HERE = R / ".agents" / "slop" / "wgslperf"
BEND = R / "bin/bend"

sys.path.insert(0, str(HERE))
import wgslbase

ACC = """globalThis.__C = globalThis.__C || {};
globalThis.__CC = (k) => { globalThis.__C[k] = (globalThis.__C[k] || 0) + 1; };"""

# **⇒⇒† AND **THE **NAMES **ARE **MATCHED **BY **THEIR **TAIL** (⇒⇒† AND **AND **THE **PORT's
# **MODULE **PATH **IS **A **PREFIX**) ✓
NAMES = [
  "UOp_toposort", "Arena_budget", "List_contains_0", "Arena_edges", "Arena_at",
  "Kahn_get", "RTable_get", "Kahn_walk", "UOp_fold", "vms_reach_go", "vms_tail_go",
  "Arena_put", "Arena_put_go", "List_append", "List_length",
  # **⇒⇒† AND **THE **FOLD's **PER-NODE **WORK**, **⇒⇒† AND **AND **THE **VMS's **LIST
  # **BUILDERS** ✓
  "fold_srcs_go", "fold_sized_go", "fold_marg_step", "fold_shapes_of_put",
  "Kahn_gather_step", "fold_set_union_go", "fold_set_del", "fold_rng_of_put",
  "vms_u_go", "vms_enc_go", "vms_row_go", "vms_cons_go", "vms_ends_go",
  "rg_rngs_go", "fold_dt_shape", "fold_least_upper_dtypes", "fold_addrspace_of",
  # **⇒⇒† AND **THE **RANGIFY's **WIDENING**, **⇒⇒† AND **AND **THE **AFT's **WALK** ✓
  "rg_afts_go", "rr_widen_end", "rr_widen_node", "rg_rngs", "rg_minus_go", "rw_ranges",
  "rr_widen", "O_UOp_toposort",
]


def find_fn(src, name):
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
          k += 1
        if src[k] == '"':
          break
        k += 1
    elif ch == "{":
      depth += 1
    elif ch == "}":
      depth -= 1
      if depth == 0:
        return i, k + 1
    k += 1
  return i, None


def main():
  # **⇒⇒† AND **THE **DRIVER **IS **THE **BUNDLE's**, **⇒⇒† AND **AND **A **`--tree`** **OVERRIDES
  # **THE **WORKING **TREE** (⇒⇒† AND **AND **THAT **IS **HOW **A **TREE **IS **MEASURED **WHILE
  # **ANOTHER **PANE **IS **MID-EDIT **IN **THE **SHARED **ONE**) ✓
  tree = (pathlib.Path(sys.argv[sys.argv.index("--tree") + 1]) / "tinybendygrad") if "--tree" in sys.argv else None
  driver = wgslbase.driver_for(tree, "countbundle")
  out = HERE / "wgslprof.count.mjs"
  b = subprocess.run([str(BEND), str(driver), "-o", str(out)],
                     capture_output=True, text=True)
  if b.returncode != 0 or not out.exists():
    raise SystemExit(f"WARN: the driver did not build:\n{b.stderr[:1200]}")
  src = out.read_text()
  found = []
  for key in NAMES:
    ms = re.findall(r"function (\$[A-Za-z0-9_]*" + re.escape(key) + r")\(", src)
    if len(ms) != 1:
      print(f"  (the {key} name matched {len(ms)} functions -- SKIPPED)")
      continue
    fname = ms[0]
    i, end = find_fn(src, fname)
    body = src[i:end]
    body = body.replace("{", "{\n  globalThis.__CC(\"" + key + "\");", 1)
    src = src[:i] + body + src[end:]
    found.append(key)
  print(f"THE COUNTED FUNCTIONS: {len(found)}  ({', '.join(found)})")
  # **⇒⇒† AND **THE **CELLS **THE **APPEND **COPIES** (⇒⇒† AND **AND **THE **RECURSION's **BODY
  # **IS **ONE **CELL **A **TIME**) ✓
  for key in ("List_append", "List_contains_0"):
    ms = re.findall(r"function (\$[A-Za-z0-9_]*" + re.escape(key) + r")\(", src)
    if len(ms) != 1:
      continue
    fname = ms[0]
    i, end = find_fn(src, fname)
    body = src[i:end]
    body = body.replace("    const _h_0 = _xs_0[\"head\"];",
                        "    globalThis.__CC(\"" + key + ".cells\");\n"
                        "    const _h_0 = _xs_0[\"head\"];", 1)
    body = body.replace("    const _t_0 = _xs_0[\"tail\"];",
                        "    globalThis.__CC(\"" + key + ".cells\");\n"
                        "    const _t_0 = _xs_0[\"tail\"];", 1)
    src = src[:i] + body + src[end:]
  m = re.search(r"function (\$chain_wgsl)\(([^)]*)\)\s*\{", src)
  if not m:
    raise SystemExit("WARN: no chain_wgsl")
  i = src.find(m.group(0))
  src = src[:i] + ACC + src[i:]
  out.write_text(src)
  call = HERE / "call-count.mjs"
  call.write_text('import M from "./wgslprof.count.mjs";\n'
                  'import fs from "fs";\n'
                  'M["chain_wgsl"]();\n'
                  'fs.writeFileSync(process.env.__WGSL_OUT || "/tmp/wgslcount.json",\n'
                  '  JSON.stringify(globalThis.__C || {}));\n')
  env = dict(subprocess.os.environ)
  env["__WGSL_OUT"] = str(HERE / "walk-counts.json")
  r = subprocess.run(["node", str(call)], capture_output=True, text=True, env=env, cwd=str(HERE))
  if r.returncode != 0:
    print(r.stderr[:1200])
    raise SystemExit("WARN: the counting driver did not run")
  C = json.loads((HERE / "walk-counts.json").read_text())
  print()
  for k in sorted(C, key=lambda k: -C[k]):
    print(f"  {k:24s} {C[k]:14,}")


if __name__ == "__main__":
  main()
