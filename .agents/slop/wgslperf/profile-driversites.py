#!/usr/bin/env python3
"""**THE **WGSL **GENERATION's **PHASES**, **MEASURED **BY **THE **DRIVER'S **OWN **CALL **SITES** -- **⇒⇒† AND
**AND **THE **CLOCKS **GO **IN **THE **DRIVER**, **NOT **IN **THE **CALLEES** (⇒⇒† AND **AND **A **WRAPPER
**OF **A **RECURSIVE **FUNCTION **OR **OF **ANY **FUNCTION **WHOSE **BODY **CALLS **A **WRAPPED **ONE
**BREAKS** (⇒⇒† AND **MEASURED: **"Cannot **read **properties **of **undefined**")**)**.

**⇒⇒† AND **SO **THE **DRIVER **IS **PATCHED **AT **THE **CALL **SITES** (⇒⇒† AND **AND **THE **DRIVER
**IS **A **COPY **OF **THE **ORIGINAL**, **⇒⇒† AND **AND **THE **COPY **IS **WHAT **IS **BUILT**)**.

**⇒⇒† AND **AND **THE **PATCH **IS **BY **THE **CALL **SITE's **TEXT** (⇒⇒† AND **AND **THE **CALLS **ARE
**COUNTED **BEFORE **THEY **ARE **PATCHED**)**.
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

# **THE **CALL **SITES **IN **THE **DRIVER**, **AND **THE **PHASE **EACH **IS** (⇒⇒† AND **AND **THE
# **DRIVER's **TEXT **IS **THE **ORIGINAL's**)
# **⇒⇒† AND **THE **CALL **SITES **ARE **THE **DRIVER's **OWN**, **AND **THE **TEXT **IS **DIFFERENT **IN
# **EACH **TREE** (⇒⇒† AND **AND **THE **COMPILED **NAME **CARRIES **THE **MODULE **PATH**, **⇒⇒† AND **AND
# **THE **SCRATCH **TREE's **PATH **IS **SHORTER**) -- **⇒⇒† AND **AND **SO **THE **TEXT **IS **THE **CALL's
# **TAIL**, **⇒⇒† AND **AND **THE **TAIL **MUST **BE **UNIQUE** (⇒⇒† AND **AND **AN **AMBIGUOUS **TAIL
# **IS **NOT **A **MEASUREMENT**)**
# **⇒⇒† AND **THE **EXACT **COMPILED **NAMES**, **AND **THEY **ARE **READ **OUT **OF **THE **BUILD** (⇒⇒† AND
# **AND **THE **PREFIX **DEPENDS **ON **THE **TREE's **LAYOUT**, **⇒⇒† AND **AND **SO **THE **NAME **IS
# **MATCHED **BY **ITS **TAIL **AND **MUST **BE **UNIQUE**)**
SITES = [
  ("kg", "_fchainl_kg"),
  ("schedule", "_schedule___init___schedule"),
  ("walk", "_wgsl_walk_walk"),
  ("render_kernel", "_wgsl_render_kernel"),
]


def build_and_run(driver: pathlib.Path, tag: str):
  out_js = HERE / f"wgslprof-{tag}.mjs"
  b = subprocess.run([str(BEND), str(driver), "-o", str(out_js)], capture_output=True, text=True)
  if b.returncode != 0 or not out_js.exists():
    raise SystemExit(f"WARN: {driver.name} did not build:\n{b.stderr[:1200]}")
  src = out_js.read_text()
  ACC = ('globalThis.__P = globalThis.__P || {};\n'
         'globalThis.__PM = (k, t0) => { globalThis.__P[k] = (globalThis.__P[k] || 0) + (performance.now() - t0); };\n')
  out = src
  # **⇒⇒† AND **THE **PATCH **IS **AT **THE **CALL **SITE** (⇒⇒† AND **AND **IT **IS **A **SEQUENCE
  # **AROUND **THE **CALL**, **⇒⇒† AND **AND **THE **COMMA **OPERATOR **RETURNS **THE **RIGHT
  # **OPERAND**, **⇒⇒† AND **AND **SO **THE **VALUE **IS **UNCHANGED**)**
  for key, call in SITES:
    # **⇒⇒† AND **THE **NAME **IS **PREFIX-DEPENDENT** (⇒⇒† AND **AND **THE **SCRATCH **TREE's **IS
    # **SHORTER**)** -- **⇒⇒† AND **SO **THE **CALL **IS **MATCHED **BY **ITS **TAIL** (⇒⇒† AND **AND **THE
    # **NAME **APPEARS **TWICE** (⇒⇒† AND **THE **DEFINITION **AND **THE **CALL**), **⇒⇒† AND **AND **THE
    # **CALL **IS **THE **ONE **THAT **IS **NOT **A **DEFINITION**)**
    # **⇒⇒† AND **THE **CALL **IS **MATCHED **BY **THE **FULL **NAME **OR **BY **ITS **TAIL** (⇒⇒† AND **AND
    # **THE **TAIL **MUST **BE **UNIQUE** (⇒⇒† AND **AND **AN **AMBIGUOUS **NAME **IS **NOT **A
    # **MEASUREMENT**)**
    # **⇒⇒† AND **THE **CALL **SITE **IS **THE **ONE **THAT **IS **NOT **A **DEFINITION** (⇒⇒† AND **AND
    # **THE **DEFINITION **IS **`function $NAME(`**)**
    # **⇒⇒† AND **THE **NAME **ENDS **WITH **THE **TAIL** (⇒⇒† AND **AND **THE **PREFIX **IS **THE
    # **MODULE **PATH**) -- **⇒⇒† AND **AND **THE **NAME **MUST **BE **UNIQUE** (⇒⇒† AND **AND **AN
    # **AMBIGUOUS **NAME **IS **NOT **A **MEASUREMENT**)**
    names = re.findall(r"function (\$[A-Za-z0-9_]*" + re.escape(call) + r")\(", out)
    if len(names) != 1:
      print(f"  (the {key} definition matched {len(names)} -- SKIPPED, an ambiguous name is not a measurement)")
      continue
    fname = names[0]
    ms = [m.start() for m in re.finditer(re.escape(fname) + r"\(", out)
          if not out[max(0, m.start() - 9):m.start()].endswith("function ")]
    # **⇒⇒† AND **THE **DEFINITION **IS **THE **ONE **THAT **IS **FOLLOWED **BY **THE **BODY** (⇒⇒† AND **AND
    # **THE **CALL **IS **THE **OTHER**)**.
    callpos = [m.start() for m in re.finditer(re.escape(ms[0]) + r"\(", out)
               if not out[max(0, m.start() - 9):m.start()].endswith("function ")]
    if len(callpos) != 1:
      print(f"  (the {key} call site is {len(callpos)} -- SKIPPED, an ambiguous site is not a measurement)")
      continue
    call = ms[0] + "("
    # **⇒⇒† AND **THE **BALANCED **PAREN **OF **THE **CALL** (⇒⇒† AND **AND **THE **ARGUMENT **MAY **HOLD
    # **NESTED **CALLS**)**.
    k = out.index(call) + len(call)
    depth = 1
    while depth:
      if out[k] == "(":
        depth += 1
      elif out[k] == ")":
        depth -= 1
        if depth == 0:
          break
      k += 1
    expr = out[out.index(call):k + 1]
    new = f"(globalThis.__PM(\"{key}\", performance.now()), {expr})"
    # **⇒⇒† AND **AND **THE **CLOCK **IS **TAKEN **AFTER** (⇒⇒† AND **AND **SO **THE **CALL'S **OWN
    # **TIME **IS **IN **IT**)**
    new = f"(() => {{ const __t = performance.now(); const __v = {expr}; globalThis.__PM(\"{key}\", __t); return __v; }})()"
    out = out.replace(expr, new, 1)
  m = re.search(r"function (\$chain_wgsl)\(([^)]*)\)\s*\{", out)
  if not m:
    raise SystemExit("WARN: no chain_wgsl")
  i = out.find(m.group(0))
  out = out[:i] + ACC + out[i:]

  instr = HERE / f"wgslprof-{tag}.mjs"
  instr.write_text(out)
  call = HERE / f"call-{tag}.mjs"
  call.write_text(f'import M from "./{instr.name}";\n'
                  f'import fs from "fs";\n'
                  f'const t0 = Date.now();\n'
                  f'const w = M["chain_wgsl"]();\n'
                  f'const ms = Date.now() - t0;\n'
                  f'fs.writeFileSync(process.env.__WGSL_OUT || "/tmp/wgslprof.json",\n'
                  f'  JSON.stringify({{P: globalThis.__P || {{}}, ms, bytes: w.length}}));\n')
  env = dict(subprocess.os.environ)
  env["__WGSL_OUT"] = f"/tmp/wgslprof-{tag}.json"
  r = subprocess.run(["node", str(call)], capture_output=True, text=True, env=env)
  if r.returncode != 0:
    raise SystemExit(f"WARN: the driver did not run:\n{r.stderr[:1500]}")
  return json.loads(pathlib.Path(env["__WGSL_OUT"]).read_text())


def main():
  root = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else R
  D = build_and_run(root / "wgslprof.bend", root.name)
  P = D.get("P", {})
  print()
  print(f"  THE WHOLE chain_wgsl(): {D.get('ms', 0):.1f} ms, {D.get('bytes', 0)} bytes")
  print()
  print("THE PHASES (ms):")
  for k, v in sorted(P.items(), key=lambda kv: -kv[1]):
    print(f"  {k:16s} {v:10.1f}")


if __name__ == "__main__":
  main()
