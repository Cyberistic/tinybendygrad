#!/usr/bin/env python3
"""**THE **PRELUDE's **`String.split`**, **CLOCKED **WITHOUT **THE **NESTING** -- **⇒⇒† AND **AND **THE
**ENTRY's **CLOCK **SPANS **THE **RECURSION**, **⇒⇒† AND **AND **SO **THE **TIME **IS **COUNTED **ONCE
**PER **LEVEL** (⇒⇒† AND **AND **THE **NESTED **CLOCKS **OVERCOUNT**)**.

**⇒⇒† AND **THE **EXCLUSIVE **WORK **OF **THE **ENTRY **IS **THE **TWO **`slice`s **AND **THE **TWO
**`char_len`s** -- **⇒⇒† AND **AND **THAT **IS **THE **BODY** (⇒⇒† AND **AND **THE **RECURSIVE **CALL
**IS **THE **OTHER **HALF**)** -- **⇒⇒† AND **AND **SO **THE **EXCLUSIVE **CLOCK **IS **TAKEN **AROUND
**THE **`slice`s **ONLY**, **⇒⇒† AND **AND **THE **RECURSION **IS **COUNTED** (⇒⇒† AND **AND **THE
**COUNT **IS **THE **CHARACTER **COUNT**)**.
"""

import json
import pathlib
import re
import sys
import time

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import portc  # noqa: E402
import noisefloor  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"

ACC = """globalThis.__Y = globalThis.__Y || {};
globalThis.__YM = (t0) => { globalThis.__Y.t = (globalThis.__Y.t || 0) + (performance.now() - t0); };
globalThis.__YN = () => { globalThis.__Y.n = (globalThis.__Y.n || 0) + 1; };"""


def instrument(src: str) -> str:
  # **THE **`slice`s **IN **THE **ENTRY's **BODY** -- **⇒⇒† AND **AND **THE **RECURSIVE **CALL **IS **LEFT
  # **ALONE** (⇒⇒† AND **AND **THE **COUNT **IS **AT **IT**)**
  old = """  } else {
    const _h_0 = _s_0.slice(0, char_len(_s_0));
    const _t_0 = _s_0.slice(char_len(_s_0));
    return $String_split_fin(_h_0, $$String_split(_t_0, _sep_0), $$Char_is_eq(_h_0, _sep_0));
  }"""
  new = """  } else {
    const __t = performance.now();
    const _h_0 = _s_0.slice(0, char_len(_s_0));
    const _t_0 = _s_0.slice(char_len(_s_0));
    globalThis.__YM(__t);
    globalThis.__YN();
    return $String_split_fin(_h_0, $$String_split(_t_0, _sep_0), $$Char_is_eq(_h_0, _sep_0));
  }"""
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the split body site is {src.count(old)}")
  src = src.replace(old, new)

  marker = "function $serve(_fuel_0, _m_0, _s_0) {"
  i = src.index(marker)
  src = src[:i] + ACC + "\n" + src[i:]

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".yc",
        JSON.stringify({Y: globalThis.__Y || {}})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  i = src.index(dump_old)
  if i < 0:
    raise SystemExit("WARN: no @@END site")
  src = src[:i] + dump_new + src[i + len(dump_old):]
  return src


def main():
  import sys as _s
  base = BUILD / (_s.argv[1] if len(_s.argv) > 1 else "serve_plus.js")
  out_path = BUILD / f"serve_ysplitx_{base.stem}.js"
  out_path.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out_path, f"ysplitx{base.stem}")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  time.sleep(0.3)
  d.stop()

  data = json.loads(pathlib.Path(str(d.cpu_file) + ".yc").read_text())
  Y = data.get("Y", {})
  n = 60
  calls = Y.get("n", 0) / n
  t = Y.get("t", 0) / n
  print()
  print(f"THE **PRELUDE's **`String.split`**, THE **EXCLUSIVE **WORK ({n} turns):")
  print(f"  the CHARACTERS a turn: {calls:.0f}")
  print(f"  the TWO SLICES + TWO char_len: {t:.4f} ms a turn")
  print(f"  **⇒⇒† AND **THE **COST **PER **CHARACTER: **{t/calls*1000:.3f} us**")


if __name__ == "__main__":
  main()
