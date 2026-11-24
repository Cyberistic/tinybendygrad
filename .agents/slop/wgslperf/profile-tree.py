#!/usr/bin/env python3
"""**THE **WGSL **GENERATION's **PHASES**, **MEASURED **IN **THE **SCRATCH **TREE** -- **⇒⇒† AND **AND
**THE **DRIVER **IS **A **COPY **OF **THE **ORIGINAL** (⇒⇒† AND **AND **THE **CLOCKS **GO **IN **THE
**COMPILED **JS**, **⇒⇒† AND **AND **SO **THE **DRIVER **IS **UNCHANGED**)**.

**⇒⇒† AND **THE **PROFILE **SITES **ARE **READ **FROM **THE **COMPILED **FORM** (⇒⇒† AND **AND **THE
**TREE's OWN **RULE**: **THE **PATCH **SITES **ARE **COUNTED **BEFORE **THEY **ARE **APPLIED**)**
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

# **THE **PHASES**, **BY **THEIR **COMPILED **NAMES** (⇒⇒† AND **AND **THEY **WERE **READ **OUT **OF **A
# **BUILD**)**
# **⇒⇒† AND **THE **TAILS** (⇒⇒† AND **AND **THE **PREFIX **DEPENDS **ON **THE **TREE's **LAYOUT**)
TARGETS = [
  ("body_kus", "runtime_device_body_kus"),
  ("body_low", "runtime_device_body_low"),
  ("wk_commit", "uop_weak_wk_commit"),
  ("late_apply", "runtime_device_late_apply"),
  ("kg", "fchainl_kg"),
  ("fold", "uop_fold_folded"),
  ("convert", "renderer_kuconv_kuconv_convert"),
  ("walk", "renderer_wgsl_walk_walk"),
  ("render_kernel", "renderer_wgsl_render_kernel"),
]


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


def resolve(src: str, tail: str):
  """**THE **COMPILED **NAME **BY **ITS **TAIL** -- **⇒⇒† AND **AND **THE **PREFIX **IS **THE **MODULE
  **PATH**, **⇒⇒† AND **AND **IT **DEPENDS **ON **WHERE **THE **TREE **IS** (⇒⇒† AND **AND **THE **SCRATCH
  **TREE's **PREFIX **IS **SHORTER**), **⇒⇒† AND **AND **SO **THE **NAME **IS **MATCHED **BY **ITS **TAIL**).

  **⇒⇒† AND **AND **THE **MATCH **MUST **BE **UNIQUE** (⇒⇒† AND **AND **A **DUPLICATE **MEANS **THE
  **NAME **IS **AMBIGUOUS** **⇒⇒† AND **AND **THEN **IT **IS **SKIPPED **RATHER **THAN **CLOCKED **WRONG**)**
  """
  ms = re.findall(r"function (\$[A-Za-z0-9_]*" + re.escape(tail) + r")\(", src)
  if len(ms) != 1:
    return None
  return ms[0]


def build_and_profile(driver: pathlib.Path, out_js: pathlib.Path, tag: str):
  b = subprocess.run([str(BEND), str(driver), "-o", str(out_js)], capture_output=True, text=True)
  if b.returncode != 0 or not out_js.exists():
    raise SystemExit(f"WARN: {driver.name} did not build:\n{b.stderr[:1200]}")
  src = out_js.read_text()
  ACC = ('globalThis.__P = globalThis.__P || {};\n'
         'globalThis.__PM = (k, t0) => { globalThis.__P[k] = (globalThis.__P[k] || 0) + (performance.now() - t0); };\n')
  out = src
  found = []
  for key, tail in TARGETS:
    fname = resolve(out, tail)
    if not fname:
      continue
    m = re.search(r"function (" + re.escape(fname) + r")\(([^)]*)\)\s*\{", out)
    if not m:
      continue
    params = m.group(1)
    i, end = find_fn(out, fname)
    body = out[i:end]
    inner = fname + "__orig"
    body = body.replace(f"function {fname}(", f"function {inner}(", 1)
    args = ", ".join(p.strip() for p in params.split(","))
    wrapper = (f"function {fname}({params}) {{\n"
               f"  const __t = performance.now();\n"
               f"  const __v = {inner}({args});\n"
               f"  globalThis.__PM(\"{key}\", __t);\n"
               f"  return __v;\n"
               f"}}")
    out = out[:i] + body + "\n" + wrapper + out[end:]
    found.append(key)
  m = re.search(r"function (\$chain_wgsl)\(([^)]*)\)\s*\{", out)
  if not m:
    raise SystemExit("WARN: no chain_wgsl")
  i = out.find(m.group(0))
  out = out[:i] + ACC + out[i:]

  instr = HERE / f"wgslprof.{tag}.mjs"
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
  t0 = time.perf_counter()
  r = subprocess.run(["node", str(call)], capture_output=True, text=True, env=env)
  if r.returncode != 0:
    raise SystemExit(f"WARN: the driver did not run:\n{r.stderr[:1200]}")
  D = json.loads(pathlib.Path(env["__WGSL_OUT"]).read_text())
  print(f"  (the clocked phases: {len(found)})")
  return D


def main():
  root = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else R
  driver = root / "wgslprof.bend"
  print(f"THE DRIVER: {driver}")
  D = build_and_profile(driver, HERE / f"wgslprof-{root.name}.mjs", root.name)
  P = D.get("P", {})
  print()
  print(f"  THE WHOLE chain_wgsl(): {D.get('ms', 0):.1f} ms, {D.get('bytes', 0)} bytes")
  print()
  print("THE PHASES (ms):")
  for k, v in sorted(P.items(), key=lambda kv: -kv[1]):
    print(f"  {k:16s} {v:10.1f}")


if __name__ == "__main__":
  main()
