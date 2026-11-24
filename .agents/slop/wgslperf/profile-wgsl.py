#!/usr/bin/env python3
"""**THE **PHASES **OF **THE **WGSL **GENERATION**, **MEASURED **IN **THE **COMPILED **JS** -- **⇒⇒† AND
**AND **THE **PAGE'S **OWN **`Date.now()`** **IS **COARSE**, **⇒⇒† AND **AND **THE **JS **LANE **HAS
**`performance.now()`**.

**WHY.** THE **23,679 ms** **WAS **MEASURED **BY **THE **PAGE**, **⇒⇒† AND **AND **IT **IS **ONE
**NUMBER** (⇒⇒† AND **THE **`chain_wgsl()`** **CALL**), **⇒⇒† AND **AND **SO **THE **PROFILE **HAS **TO
**SPLIT **IT**.

**⇒⇒† AND **THE **PHASES **ARE **THE **DRIVER's **OWN **STEPS** (⇒⇒† AND **AND **THE **DRIVER **IS
**`.agents/slop/browser/fchainwgsl.bend`**): **THE **`kg()`** **BUILD**, **THE **`schedule()`**, **THE
**`lin_kernels()`**, **AND **THE **PER-KERNEL **`W.walk()` **+ **`V.render_kernel()`**.

**⇒⇒† AND **AND **THE **CLOCKS **ARE **IN **THE **COMPILED **FORM** (⇒⇒† AND **AND **THE **TREE's OWN
**RULE**: **THE **PATCH **SITES **ARE **READ **FROM **THE **COMPILED **FORM**)**.
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


def build() -> pathlib.Path:
  """**THE **DRIVER **COMPILED **TO **JS** -- **⇒⇒† AND **THE **BUILD **IS **INSIDE **THE
  **MEASUREMENT** (⇒⇒† AND **AND **A **STALE **BUILD **IS **A **SECOND **SOURCE **OF **TRUTH**)**."""
  out = HERE / "wgslprof.mjs"
  b = subprocess.run([str(BEND), str(HERE / "wgslprof.bend"), "-o", str(out)],
                     capture_output=True, text=True)
  if b.returncode != 0 or not out.exists():
    raise SystemExit(f"WARN: the driver did not build:\n{b.stderr[:1500]}")
  return out


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


def instrument(src: str) -> str:
  """**THE **CLOCKS **AT **THE **PHASE **SITES** -- **⇒⇒† AND **AND **THE **SITES **ARE **THE **COMPILED
  # **FORM's **OWN **CALLS** (⇒⇒† AND **AND **EVERY **SITE **IS **COUNTED **BEFORE **IT **IS
  # **PATCHED**)"""
  ACC = ('globalThis.__P = globalThis.__P || {};\n'
         'globalThis.__PM = (k, t0) => { globalThis.__P[k] = (globalThis.__P[k] || 0) + (performance.now() - t0); };\n')

  # **THE **PHASES **AND **THEIR **COMPILED **NAMES** -- **⇒⇒† AND **AND **THE **NAMES **ARE **THE
  # **COMPILED **FORM's **OWN** (⇒⇒† AND **AND **THE **PORT's **MODULE **PREFIX **IS
  # **`_tinybendygrad_...`**)**.
  # **⇒⇒† AND **THE **NAMES **ARE **THE **COMPILED **FORM's **OWN** (⇒⇒† AND **AND **THEY **WERE **READ
  # **OUT **OF **THE **BUILD**, **⇒⇒† AND **AND **THE **PORT's **MODULE **SEPARATOR **IS **`_`** (⇒⇒† AND
  # **AND **THE **`schedule/__init__.bend`** **BECOMES **`schedule___init___`**)**.
  TARGETS = [
    ("kg", "$___browser_fchainl_kg"),
    ("schedule", "$_________tinybendygrad_schedule___init___schedule"),
    ("lin_kernels", "$_________tinybendygrad_schedule___init___lin_kernels"),
    ("lin_ar", "$_________tinybendygrad_schedule___init___lin_ar"),
    ("walk", "$_________tinybendygrad_renderer_wgsl_walk_walk"),
    ("render_kernel", "$_________tinybendygrad_renderer_wgsl_render_kernel"),
    ("body_kus", "$_________tinybendygrad_runtime_device_body_kus"),
    ("ku2r_l", "$___browser_ku2r_ku2r_l"),
    # **⇒⇒† AND **THE **FOUR **STEPS **OF **`body_kus`** (⇒⇒† AND **AND **THEY **ARE **THE **SUSPECTS
    # **NOW **THAT **`body_kus` **IS **76% **OF **THE **TIME**)**
    ("bk_toposort", "$_________tinybendygrad_uop_ops_toposort"),
    ("bk_linearize", "$_________tinybendygrad_codegen_late_linearizer_linearize"),
    ("bk_fold", "$_________tinybendygrad_codegen_decomp_op_dc_l_fold"),
    ("bk_convert", "$_________tinybendygrad_renderer_kuconv_kuconv_convert"),
    ("bk_body_low", "$_________tinybendygrad_runtime_device_body_low"),
    ("bk_budget", "$_________tinybendygrad_uop_ops_Arena_budget"),
    ("bk_sc_src0", "$_________tinybendygrad_schedule___init___sc_src0"),
    ("bk_vms", "$_________tinybendygrad_runtime_device_vms"),
    # **⇒⇒† AND **THE **FIVE **STEPS **OF **`body_low`** (⇒⇒† AND **AND **`body_low` **IS **71% **OF **THE
    # **WHOLE**)**
    ("bl_wk_commit", "$_________tinybendygrad_uop_weak_wk_commit"),
    ("bl_lower_reduce_all", "$_________tinybendygrad_codegen_kernel_lower_reduce_all"),
    ("bl_late_apply", "$_________tinybendygrad_runtime_device_late_apply"),
    ("bl_alloc_to_buf_all", "$_________tinybendygrad_codegen_kernel_alloc_to_buf_all"),
    ("bl_add_loads", "$_________tinybendygrad_runtime_device_add_loads"),
  ]
  out = src
  found = []
  for key, name in TARGETS:
    m = re.search(r"function (" + re.escape(name) + r")\(([^)]*)\)\s*\{", out)
    if not m:
      print(f"  (the {key} phase is NOT in the compiled form -- the name is different)")
      continue
    fname, params = m.group(1), m.group(2)
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
    found.append((key, fname))
  print(f"THE CLOCKED PHASES: {len(found)}  ({', '.join(k for k, _ in found)})")

  # **THE **ACCUMULATOR**, **AND **THE **DUMP** (⇒⇒† AND **AND **THE **`main` **IS **NOT **EXPORTED
  # **BY **THE **`-o` **BUILD** (⇒⇒† AND **AND **THE **EXPORT **LIST **HAS **THE **DEFS **BUT **NOT
  # **`main`**) -- **⇒⇒† AND **AND **`chain_wgsl` **IS **THE **WHOLE **THING**).
  m = re.search(r"function (\$chain_wgsl)\(([^)]*)\)\s*\{", out)
  if not m:
    raise SystemExit("WARN: no chain_wgsl")
  i = out.find(m.group(0))
  out = out[:i] + ACC + out[i:]

  # **⇒⇒† AND **THE **DUMP **GOES **IN **THE **CALL **DRIVER** (⇒⇒† AND **AND **THE **DRIVER **IS **THE
  # **ONE **THAT **CALLS **`chain_wgsl()`**, **⇒⇒† AND **AND **SO **THE **TIMES **ARE **THERE **WHEN **IT
  # **RETURNS**)**.
  return out


def main():
  base = build()
  src = base.read_text()
  out = HERE / "wgslprof.instr.mjs"
  out.write_text(instrument(src))
  chk = subprocess.run(["node", "--check", str(out)], capture_output=True, text=True)
  if chk.returncode != 0:
    raise SystemExit(f"WARN: the instrumented build does not parse:\n{chk.stderr[:1500]}")
  print("THE INSTRUMENTED BUILD PARSES")

  env = dict(subprocess.os.environ)
  env["__WGSL_OUT"] = "/tmp/wgslprof.json"
  # **⇒⇒† AND **THE **DRIVER **IS **A **MODULE** (⇒⇒† AND **AND **THE **`-o` **BUILD **EXPORTS **THE
  # **DEFS **BUT **NOT **`main`**) -- **⇒⇒† AND **AND **SO **THE **CALL **IS **A **ONE-LINE **DRIVER**
  # **THAT **CALLS **`chain_wgsl()`** (⇒⇒† AND **AND **THAT **IS **WHAT **THE **PAGE **DOES**)**
  call = HERE / "call.mjs"
  call.write_text('import M from "./wgslprof.instr.mjs";\n'
                  'import fs from "fs";\n'
                  'const t0 = Date.now();\n'
                  'const w = M["chain_wgsl"]();\n'
                  'const ms = Date.now() - t0;\n'
                  'fs.writeFileSync(process.env.__WGSL_OUT || "/tmp/wgslprof.json",\n'
                  '  JSON.stringify({P: globalThis.__P || {}, ms, bytes: w.length}));\n'
                  'console.log("bytes=" + w.length + " ms=" + ms);\n')
  t0 = time.perf_counter()
  b = subprocess.run(["node", str(call)], capture_output=True, text=True, env=env)
  wall = (time.perf_counter() - t0) * 1000
  if b.returncode != 0:
    print(b.stderr[:1500])
    raise SystemExit("WARN: the driver did not run")
  print()
  print(f"THE WHOLE DRIVER: {wall:.1f} ms (the node process, including the start-up)")
  try:
    D = json.loads(pathlib.Path("/tmp/wgslprof.json").read_text())
  except Exception as e:
    print("WARN: no dump:", e)
    return
  P = D.get("P", {})
  print(f"  THE WHOLE chain_wgsl(): {D.get('ms', 0):.1f} ms, {D.get('bytes', 0)} bytes")
  print()
  print("THE PHASES (ms):")
  for k, v in sorted(P.items(), key=lambda kv: -kv[1]):
    print(f"  {k:14s} {v:10.1f}")
  print()
  print(f"  THE SUM OF THE PHASES: {sum(P.values()):.1f} ms")


if __name__ == "__main__":
  main()
