#!/usr/bin/env python3
"""COUNT **THE `ku_op_at` INDEX SEQUENCE**, AND **HOW MANY TIMES **EACH INDEX** IS LOOKED UP**.

**WHY:** MEASURED: **`ku_op_at` RUNS **2,378** TIMES A TURN** (MEASURED, IN THE DAEMON) **AND
EACH ONE WALKS **A TWO-LEVEL INDEX** (`i/16` **INTO **THE KERNEL LIST** AND `i%16` **INTO **THE
BLOCK**) -- **⇒⇒⇒ AND **THE ALU's SOURCE LOOP WALKS **THE **SAME** SOURCE ROWS** **AGAIN AND
AGAIN** (ONCE PER ALU UOP), **⇒⇒⇒ SO **THE QUESTION IS **WHETHER **THE SAME INDEX** IS LOOKED
UP **REPEATEDLY**, **AND **IF SO, **WHETHER **A CACHE OR **A DIFFERENT SHAPE** IS **THE WIN**.

**⇒⇒⇒ AND **THE SEQUENCE IS **COUNTED**, NOT GUESSED** -- **AND **A COUNT OF **THE INDEX
SEQUENCE** IS **A COUNT OF **THE WALK**, **AND **THE WALK IS **WHAT `List.get` DOES ANYWAY**,
**⇒⇒⇒ SO **THE INSTRUMENT'S COST IS **THE COST IT MEASURES**."""

import json
import pathlib
import sys
import time

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import portc  # noqa: E402
import noisefloor  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"

ACC = "globalThis.__X = {seq: [], n:0};"


def instrument(src: str) -> str:
  old = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old)}")
  src = src.replace(old, ACC + "\n" + old, 1)

  # **THE INDEX SEQUENCE, AT **THE `ku_op_at` CALL** IN `ku_alu_srcs_go`.**
  # **⇒⇒⇒ AND **THE SITE IS **FOUND BY **THE **CALL's TEXT**, NOT **BY **A LINE NUMBER** --
  # **AND **THE `_h_0` IS **THE ROW INDEX** (THE SOURCE's INDEX)**.
  # **⇒⇒⇒ AND **THE MARKER MUST INCLUDE **THE `$$` PREFIX** -- BECAUSE **THE REPLACEMENT
  # RE-EMITS **THE WHOLE CALL**, **AND **IF **THE MARKER** DID **NOT** INCLUDE **THE PREFIX**
  # THEN **THE PREFIX WOULD BE **LEFT BEHIND** AND **THE COMMA EXPRESSION **WOULD SPLIT **THE
  # GLOBAL NAME** -- **MEASURED: THE DAEMON EXITED** WITH
  # "`$$_________tinybendygrad_renderer_` is not defined".
  marker = "$$_________tinybendygrad_renderer_cstyle_ku_op_at(_kus_0, _h_0)"
  if src.count(marker) != 1:
    raise SystemExit(f"WARN: the ku_op_at call site is {src.count(marker)}")
  i = src.index(marker)
  # **THE INDEX IS `_h_0`** -- **AND **THE SEQUENCE IS **PUSHED** ONTO **THE ACCUMULATOR**.
  # **⇒⇒⇒ AND **THE `$$` PREFIX** IS **THE COMPILED FORM's GLOBAL NAME**, **AND **IT IS **NOT
  # **A JS TEMPLATE `${`** -- **SO **IT IS **WRITTEN **AS **`$$`**, NOT **`${`** (MEASURED:
  # **THE FIRST FORM READ `$$_________tinybendygrad_renderer_` AS **A TEMPLATE** AND **THE
  # DAEMON EXITED** WITH "is not defined").
  src = (src[:i]
         + "((globalThis.__X.seq.push(_h_0), 0), "
         + "$$_________tinybendygrad_renderer_cstyle_ku_op_at(_kus_0, _h_0))"
         + src[i + len(marker):])

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    globalThis.__X.n = (globalThis.__X.n || 0) + 1;
    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__X || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  if src.count(dump_old) != 1:
    raise SystemExit(f"WARN: the @@END site is {src.count(dump_old)}")
  src = src.replace(dump_old, dump_new, 1)
  return src


if __name__ == "__main__":
  base = BUILD / "now.js"
  out = BUILD / "serve_seq.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, "seq")
  d.start()
  time.sleep(0.8)
  for _ in range(20):
    d.turn()
  d.stop()
  X = json.loads((BUILD.parent / "nf-seq/cpu.json.d").read_text())
  n = max(X.get("n", 1), 1)
  seq = X.get("seq", [])
  # **THE LAST TURN's SEQUENCE** (THE DUMP IS **THE ACCUMULATOR**, AND **IT IS **NOT RESET**,
  # **SO **IT IS **EVERY TURN's** -- **⇒⇒⇒ AND **THE RATIOS ARE **WHAT MATTER**).
  per = len(seq) // n if n else 0
  last = seq[-per:] if per else []
  from collections import Counter
  c = Counter(last)
  print(f"\nTHE `ku_op_at` INDEX SEQUENCE: {per} CALLS A TURN, {len(c)} DISTINCT INDICES")
  print(f"  **⇒⇒⇒ SO **THE REPEAT FACTOR IS **{per / max(len(c), 1):.2f}x**")
  print(f"  THE MOST-LOOKED-UP INDICES: {c.most_common(8)}")
  print(f"  THE WALK COST (i/16 + i%16) FOR THE HOT ONES:")
  tot = 0
  for idx, n2 in c.most_common(8):
    walk = (idx >> 4) + (idx & 15)
    tot += walk * n2
    print(f"    INDEX {idx:4d}  LOOKED UP {n2:5d} TIMES  ->  {walk:3d} ELEMENTS WALKED EACH")
  allwalk = sum(((i >> 4) + (i & 15)) * v for i, v in c.items())
  print(f"\n  THE TOTAL ELEMENTS WALKED A TURN: ~{allwalk // max(n, 1)}")
  print()
  print("  **⇒⇒⇒ AND **THE `ku_at` WALK IS **THE **2,378** CALLS' COST**, AND **THE REPEAT")
  print("  FACTOR IS **HOW MUCH **A CACHE** COULD SAVE****.")
