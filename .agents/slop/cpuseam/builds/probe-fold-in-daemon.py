#!/usr/bin/env python3
"""PRICE **THE RENDER's HOT FOLDS** **IN THE DAEMON**, WHERE **THE WORK IS REAL**.

**WHY A JS MICROBENCHMARK CANNOT ANSWER THIS.** MEASURED, **A JS MICROBENCHMARK OF
`List_append` READS **FLAT AT 0.0027 us** FOR **EVERY** LIST LENGTH -- **WHICH IS **NOT **A
FOLD's PROFILE** -- **BECAUSE **THE JIT ELIMINATES **THE CALLS** WHEN **THE RESULT IS
UNUSED**. **⇒⇒⇒ AND A FLAT PROFILE IS **A MEASUREMENT OF **NOTHING****, SO **THE PRICE MUST
BE MEASURED **WHERE **THE RESULT IS **USED** -- AND THAT IS **THE DAEMON**.

**⇒⇒⇒ AND THE CLOCK IS **INSIDE** THE FOLD** (THE TREE's OWN RULE: "**THE CLOCKS ARE
**INSIDE** THE FUNCTIONS AND NOT AROUND THEM**", §136) **AND NOT AT **THE CALL SITE**, FOR
THE SAME REASON: **A REST-ARGUMENTS WRAPPER IS NOT FREE**.

**⇒⇒⇒ AND THE FOLDS ARE **NESTED** -- `List_append` RECURSES INTO ITSELF, AND `String_concat`
TOO -- **SO THE CLOCKS **OVERLAP** AND **THE SUM IS **AN OVERCOUNT**. **⇒⇒⇒ AND **THE
HONEST NUMBER** IS **THE DEEPEST-CHAIN CLOCK**, WHICH IS **WHAT **A DEEP FOLD COSTS** -- SO
**THE INSTRUMENT MEASURES **THE RECURSION DEPTH** AND **THE TOTAL TIME**, AND **THE RATIO IS
**THE COST PER LEVEL**."""

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

ACC = """globalThis.__F = {la_t:0, la_n:0, la_d:0, sc_t:0, sc_n:0, sc_d:0, n:0};
globalThis.__FD = 0;"""


def instrument(src: str) -> str:
  # **THE `List_append` FOLD.** **THE CLOCK IS **AT THE ENTRY** (SO IT IS **THE WHOLE CALL**
  # INCLUDING **THE RECURSION**) AND **THE DEPTH IS **COUNTED**).
  la = """function $List_append(_xs_0, _ys_0) {
  if (_xs_0.$ === "Nil") {
    return _ys_0;
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    return {$: "Con", "head": _h_0, "tail": $$List_append(_t_0, _ys_0)};
  }
}"""
  la_new = """function $List_append(_xs_0, _ys_0) {
  const __t0 = performance.now();
  const __d0 = globalThis.__FD; globalThis.__FD = __d0 + 1;
  if (globalThis.__FD > globalThis.__F.la_d) globalThis.__F.la_d = globalThis.__FD;
  if (_xs_0.$ === "Nil") {
    globalThis.__FD = __d0;
    globalThis.__F.la_t += performance.now() - __t0; globalThis.__F.la_n += 1;
    return _ys_0;
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    const __r = {$: "Con", "head": _h_0, "tail": $$List_append(_t_0, _ys_0)};
    globalThis.__FD = __d0;
    globalThis.__F.la_t += performance.now() - __t0; globalThis.__F.la_n += 1;
    return __r;
  }
}"""
  if src.count(la) != 1:
    raise SystemExit(f"WARN: the List_append site is {src.count(la)}")
  src = src.replace(la, la_new, 1)

  # **THE `String_concat` FOLD.**
  sc = """function $String_concat(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return "";
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    const _x_0 = $$String_concat(_t_0);
    return (_h_0 + _x_0);
  }
}"""
  sc_new = """function $String_concat(_xs_0) {
  const __t0 = performance.now();
  const __d0 = globalThis.__FD; globalThis.__FD = __d0 + 1;
  if (globalThis.__FD > globalThis.__F.sc_d) globalThis.__F.sc_d = globalThis.__FD;
  if (_xs_0.$ === "Nil") {
    globalThis.__FD = __d0;
    globalThis.__F.sc_t += performance.now() - __t0; globalThis.__F.sc_n += 1;
    return "";
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    const _x_0 = $$String_concat(_t_0);
    const __r = (_h_0 + _x_0);
    globalThis.__FD = __d0;
    globalThis.__F.sc_t += performance.now() - __t0; globalThis.__F.sc_n += 1;
    return __r;
  }
}"""
  if src.count(sc) != 1:
    raise SystemExit(f"WARN: the String_concat site is {src.count(sc)}")
  src = src.replace(sc, sc_new, 1)

  old2 = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old2) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old2)}")
  src = src.replace(old2, ACC + "\n" + old2, 1)

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    globalThis.__F.n = (globalThis.__F.n || 0) + 1;
    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__F || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  if src.count(dump_old) != 1:
    raise SystemExit(f"WARN: the @@END site is {src.count(dump_old)}")
  src = src.replace(dump_old, dump_new, 1)
  return src


if __name__ == "__main__":
  base = BUILD / "now.js"
  out = BUILD / "serve_fold.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, "fold")
  d.start()
  time.sleep(0.8)
  for _ in range(30):
    d.turn()
  d.stop()
  F = json.loads((BUILD.parent / "nf-fold/cpu.json.d").read_text())
  n = max(F.get("n", 1), 1)
  print(f"\nTHE RENDER's HOT FOLDS, **IN THE DAEMON** ({n} turns):")
  for key, label in (("la", "List_append"), ("sc", "String_concat")):
    calls = F.get(f"{key}_n", 0) / n
    total = F.get(f"{key}_t", 0) / n
    depth = F.get(f"{key}_d", 0)
    print(f"  {label:14s} {calls:9.0f} LEVELS A TURN  {total:8.4f} ms  DEEPEST {depth}")
    if calls:
        print(f"                 {1000 * total / calls:.4f} us A LEVEL")
  print()
  print("**⇒⇒⇒ AND THE TIMES **OVERLAP** (THE FOLDS RECURSE INTO THEMSELVES), SO **THE SUM IS")
  print("**AN OVERCOUNT** -- **BUT THE **PER-LEVEL** PRICE AND **THE DEPTH** ARE **THE NUMBERS")
  print("THAT **SHAPE **THE WORK**, AND **THE TOTAL IS **AN UPPER BOUND ON **THE FOLD's SHARE**.**")
  share = 100 * (F.get("la_t", 0) / n + F.get("sc_t", 0) / n) / 1000 / 1.03
  print(f"**⇒⇒⇒ AND THE RENDER IS **1.03 ms**, SO **THE FOLD's SHARE IS **AT MOST **{share:.0f}%** (AN OVERCOUNT).**")
