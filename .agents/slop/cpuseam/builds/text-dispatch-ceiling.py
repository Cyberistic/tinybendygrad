#!/usr/bin/env python3
"""**THE **CEILING **OF **THE **`ku_text_go` **DISPATCH**, **MEASURED **BY **REPLACING **THE **CHAIN
**WITH **A **DIRECT **LOOKUP** -- **⇒⇒† AND **AND **THE **OUTPUT **IS **WRONG **ON **PURPOSE** (⇒⇒†
**AND **AND **THE **POINT **IS **THE **TIMING**)**.

**WHY.** **THE **COMPILED **FORM**'s **`ku_text_go`** **IS **A **17-ARM **`===` **CHAIN **ON **THE
**OP **TAG** (⇒⇒† AND **MEASURED**, **THE **COMPILED **FORM**)** -- **⇒⇒† AND **AND **THE **ALU **ARM
**IS **THE **LAST **ONE** (⇒⇒† AND **AND **SO **AN **ALU **UOP **PAYS **ALL **17 **COMPARISONS**)**.
**⇒⇒† AND **AND **THE **DISPATCH **IS **0.907 ms **A **TURN **OVER **644 **CALLS** (⇒⇒† AND **MEASURED**
**BY **`text-family-shape.py`**) -- **⇒⇒† AND **AND **THAT **IS **THE **BIGGEST **LEAF **THE **`text`
**FAMILY **HAS**, **⇒⇒† AND **AND **IT **IS **THE **ONE **§138.3's **`render-shape.py`** **COUNTED
**AND **DID **NOT **CLOCK**.

**⇒⇒† AND **§138's **LESSON **APPLIES**: **THE **COUNT **IS **NOT **THE **COST** (⇒⇒† AND **BUT **THE
**COUNT **MULTIPLIES **THE **COST**)** -- **⇒⇒† AND **AND **THE **COUNT **IS **17 **COMPARISONS **A
**CALL**.
"""

import json
import pathlib
import re
import subprocess
import sys
import time

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import portc  # noqa: E402
import noisefloor  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"

WALL_OLD = """    return $IO_bind((_x_11) => $IO_print($$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9), _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
WALL_NEW = """    const __t0 = performance.now();
    const __r = $$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9);
    { const __c = globalThis.__W || (globalThis.__W = []); __c.push({w: performance.now() - __t0}); }
    return $IO_bind((_x_11) => $IO_print(__r, _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
DUMP_OLD = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
DUMP_NEW = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".w",
        JSON.stringify({W: globalThis.__W || []})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""


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


def patch(src: str) -> str:
  """**THE **CHAIN **IS **REPLACED **BY **A **SWITCH**-LIKE **LOOKUP** -- **⇒⇒† AND **AND **THE
  **SIMPLEST **FORM **OF **"NOT **A **CHAIN"** **IN **JS **IS **AN **OBJECT **OF **FUNCTIONS** (⇒⇒† AND
  **AND **A **`switch` **ON **A **STRING **IS **ALSO **A **CHAIN**, **⇒⇒† AND **AND **SO **THE **POINT
  **IS **THE **CEILING**, **⇒⇒† AND **AND **NOT **THE **FORM**)**."""
  name = "$_________tinybendygrad_renderer_cstyle_ku_text_go"
  i, end = find_fn(src, name)
  body = src[i:end]
  # **⇒⇒† AND **THE **CHAIN **IS **A **SEQUENCE **OF **`else if`** (⇒⇒† AND **AND **THE **ARM's
  # **BODY **IS **THE **CALL**, **⇒⇒† AND **AND **THE **LAST **ARM **IS **THE **ALU**) -- **⇒⇒† AND
  # **AND **THE **CEILING **IS **MEASURED **BY **REPLACING **THE **WHOLE **BODY **WITH **A **MAP
  # **LOOKUP **THAT **CALLS **THE **SAME **ARM** -- **⇒⇒† AND **AND **THE **MAP **IS **BUILT **ONCE**
  # (⇒⇒† AND **AND **THAT **IS **THE **ADVANTAGE **OF **THE **FORM**)**
  arms = re.findall(r'_op_0\.\$ === "([A-Za-z0-9_]+)"\) \{\s*(return [^;]+);', body)
  print(f"THE ARMS FOUND: {len(arms)}")
  if not arms:
    raise SystemExit("WARN: no arms found")
  # **⇒⇒† AND **THE **MAP **IS **A **SWITCH-LIKE **LOOKUP** -- **⇒⇒† AND **AND **THE **BODY **IS
  # **REBUILT **FROM **THE **ARMS** (⇒⇒† AND **AND **THE **ALU **ARM **IS **THE **`else`**)**
  #
  # **⇒⇒† AND **THE **ARM's **BODY **ALREADY **STARTS **WITH **`return`** (⇒⇒† AND **MEASURED: **THE
  # **REGEX **CAPTURES **`return ...`**), **⇒⇒† AND **AND **SO **THE **REBUILD **MUST **NOT **ADD **A
  # **SECOND **ONE** (⇒⇒† AND **MEASURED: **THE **FIRST **BUILD **WROTE **`return return ...;`** **AND
  # **THE **DAEMON **DIED **ON **IT**)**.
  lines = []
  for tag, ret in arms[:-1]:
    lines.append(f'    case "{tag}": {ret};')
  last = arms[-1]
  lines.append(f'    default: {last[1]};')
  new = (f"function {name}(_op_0, _dev_0, _i_0, _k_0, _kus_0, _r_0) {{\n"
         f"  switch (_op_0.$) {{\n" + "\n".join(lines) + "\n  }\n}")
  # **⇒⇒† AND **THE **REBUILD **IS **CHECKED **BEFORE **IT **IS **USED** (⇒⇒† AND **AND **A **BROKEN
  # **BUILD **HUNGS **THE **WHOLE **MEASUREMENT**)**
  if "return return" in new:
    raise SystemExit("WARN: the rebuild has a doubled return")
  return src[:i] + new + src[end:]


def build(name: str, s: str) -> pathlib.Path:
  s = s.replace(WALL_OLD, WALL_NEW).replace(DUMP_OLD, DUMP_NEW)
  p = BUILD / name
  p.write_text(s)
  # **⇒⇒† AND **THE **BUILD **IS **PARSED **BEFORE **IT **IS **USED** (⇒⇒† AND **AND **A **BROKEN
  # **BUILD **HANGS **THE **WHOLE **MEASUREMENT** -- **MEASURED: **THE **FIRST **BUILD **WROTE
  # **`return return ...;`** **AND **THE **THREE **DAEMONS **SAT **AT **0% **CPU **FOR **4m30s**)**
  #
  # **⇒⇒† AND **THE **PARSE **IS **`node --check`** (⇒⇒† AND **AND **THE **RUNTIME **IS **BUN**, **⇒⇒†
  # **AND **AND **THE **PARSE **IS **NODE** -- **⇒⇒† AND **AND **THE **PARSE **IS **A **GATE **ON **THE
  # **BUILD**, **⇒⇒† AND **AND **NOT **A **PART **OF **THE **MEASUREMENT**)**
  chk = subprocess.run(["node", "--check", str(p)], capture_output=True, text=True)
  if chk.returncode != 0:
    raise SystemExit(f"WARN: {name} does not parse:\n{chk.stderr[:600]}")
  return p


def main():
  base = BUILD / "serve_plus.js"
  src = base.read_text()
  a = build("serve_td_base.js", src)
  b = build("serve_td_switch.js", patch(src))
  dc = build("serve_td_noise.js", src)
  da = noisefloor.Daemon(a, "tdbase")
  db = noisefloor.Daemon(b, "tdswitch")
  dd = noisefloor.Daemon(dc, "tdnoise")
  da.start()
  db.start()
  dd.start()
  time.sleep(1.2)
  for _ in range(150):
    da.turn()
    db.turn()
    dd.turn()
  time.sleep(0.3)
  da.stop()
  db.stop()
  dd.stop()

  def walls(tag):
    p = pathlib.Path(str(BUILD.parent / f"nf-{tag}" / "cpu.json") + ".w")
    return sorted(w["w"] for w in json.loads(p.read_text()).get("W", []))

  A, B, C = walls("tdbase"), walls("tdswitch"), walls("tdnoise")
  print()
  print("THE **RENDER's **WALL**, **THE **BASELINE**, **THE **SWITCH**, **AND **THE **NOISE **FLOOR**:")
  print("  A (the baseline):    min %.4f  median %.4f" % (A[0], A[len(A) // 2]))
  print("  B (the switch):     min %.4f  median %.4f" % (B[0], B[len(B) // 2]))
  print("  C (the noise floor): min %.4f  median %.4f" % (C[0], C[len(C) // 2]))
  print()
  print("  **THE **CEILING**: the minima %.4f   the medians %.4f"
        % (B[0] / A[0], B[len(B) // 2] / A[len(A) // 2]))
  print("  **AND **THE **NOISE **FLOOR**: the minima %.4f   the medians %.4f"
        % (C[0] / A[0], C[len(C) // 2] / A[len(A) // 2]))


if __name__ == "__main__":
  main()
