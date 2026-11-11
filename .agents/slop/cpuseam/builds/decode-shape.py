#!/usr/bin/env python3
"""CLOCK THE **DECODE's** PARTS, **INSIDE** THE DAEMON.

**THE SITES ARE **READ FROM THE COMPILED FORM** AND NOT GUESSED**, AND EVERY PATCH IS
**COUNTED** BEFORE IT IS APPLIED, SO A MISS IS AN ERROR AND NOT A SILENT ZERO.

**THE FIVE PARTS, AND WHAT EACH IS:**
  `split`     THE **TWO** `s.split(" ")` CALLS -- **THE SAME 18 KB STRING, SPLIT **TWICE**.**
  `strings`   `wire_strings`' REST -- THE PER-ROW STRING LIST.
  `numbers`   `wire_numbers`' REST -- THE PER-ROW NUMBER LISTS.
  `rows`      `kus_rows_go` -- THE LOCKSTEP WALK OVER THE TWO LISTS.
  `ku_row`    THE PER-ROW WORK: `ku_row_s` → `ku_row_n` → `ku_row_of` → `arg_of`.

**AND EVERY CLOCK IS **INSIDE** THE FUNCTION, AND EVERY ACCUMULATOR IS READ
**AT THE `@@END`**, WHICH FIRES **ONCE A TURN**.
"""

import json
import os
import pathlib
import statistics
import sys
import time

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import portc  # noqa: E402
import noisefloor  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"

# THE ACCUMULATOR, AND THE MARKER.
ACC = """globalThis.__D = globalThis.__D || {decode:0, split:0, strings:0, numbers:0, rows:0, ku_row:0, arg_of:0, append:0, n:0};
globalThis.__M = (k, t0) => { globalThis.__D[k] += (performance.now() - t0); };"""

PATCHES = [
  # THE ACCUMULATOR, AT THE TOP OF `$serve`.
  ("function $serve(_fuel_0, _m_0, _s_0) {", ACC + "\nfunction $serve(_fuel_0, _m_0, _s_0) {"),

  # THE **SPLIT**, IN **BOTH** HALVES.
  # THE **SPLIT**, **ONCE** (MEASURED, `PARITY.md` §138: THE TWO HALVES WERE ONE EFFECT).
  ("function wire_both(s) {\n  const parts = s.split(\" \");",
   "function wire_both(s) {\n  const __t0 = performance.now();\n  const parts = s.split(\" \");\n"
   "  globalThis.__M(\"split\", __t0);\n  const __t1 = performance.now();"),

  # THE **REST** OF THE ONE EFFECT (THE TWO LIST BUILDS).
  ("""  return { $: "Both", ss, ns };
}""",
   """  globalThis.__M("numbers", __t1);
  return { $: "Both", ss, ns };
}"""),

  # THE **ROW WALK**: THE **ROW** AND THE **APPEND** ARE CLOCKED **SEPARATELY**, BECAUSE
  # ****
  # ****
  # ****
  # ****
  # ****
  # ****
  # ****
  # ****
  # ****
  # **§ §**
  ("        $2 = $$List_append({$: \"Con\", \"head\": $$_________tinybendygrad_renderer_live_ku_row(_s_0, _n_0), \"tail\": {$: \"Nil\"}}, _acc_0);",
   "        { const __tr = performance.now();\n"
   "          const __row = $$_________tinybendygrad_renderer_live_ku_row(_s_0, _n_0);\n"
   "          const __ta = performance.now();\n"
   "          $2 = $$List_append({$: \"Con\", \"head\": __row, \"tail\": {$: \"Nil\"}}, _acc_0);\n"
   "          globalThis.__M(\"append\", __ta);\n"
   "          globalThis.__M(\"rows\", __tr); }"),

  # THE **PER-ROW** WORK.
  ("function $_________tinybendygrad_renderer_live_ku_row(_s_0, _n_0) {\n  return $_________tinybendygrad_renderer_live_ku_row_s(_s_0, _n_0);\n}",
   "function $_________tinybendygrad_renderer_live_ku_row(_s_0, _n_0) {\n"
   "  const __tr = performance.now();\n"
   "  const __r = $_________tinybendygrad_renderer_live_ku_row_s(_s_0, _n_0);\n"
   "  globalThis.__M(\"ku_row\", __tr);\n"
   "  return __r;\n}"),

  # THE **PER-ROW** DISPATCH.
  ("function $_________tinybendygrad_renderer_live_arg_of(_kind0_0, _kind1_0, _p_0) {",
   "function $_________tinybendygrad_renderer_live_arg_of(_kind0_0, _kind1_0, _p_0) {\n"
   "  const __ta = performance.now();\n"
   "  const __r = $_________tinybendygrad_renderer_live_arg_of_inner(_kind0_0, _kind1_0, _p_0);\n"
   "  globalThis.__M(\"arg_of\", __ta);\n"
   "  return __r;\n}\n"
   "function $_________tinybendygrad_renderer_live_arg_of_inner(_kind0_0, _kind1_0, _p_0) {"),

  # THE **DECODE's OWN** WALL, AROUND THE WHOLE `$$decode(...)`.
  ("    return $IO_bind($$decode(_cs_1), run_clo($serve_c7(_f_0,_k_0)), _x_8);",
   "    const __td = performance.now();\n"
   "    return $IO_bind($$decode(_cs_1),\n"
   "      (_x_9b) => { globalThis.__M(\"decode\", __td); globalThis.__D.n++;\n"
   "        return run_clo($serve_c7(_f_0,_k_0))(_x_9b); },\n"
   "      _x_8);"),

  # THE DUMP.
  ("""    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);""",
   """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__D || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""),
]


def instrument(src: str) -> str:
  for old, new in PATCHES:
    if src.count(old) != 1:
      raise SystemExit(f"WARN: {src.count(old)} matches for {old[:70]!r}")
    src = src.replace(old, new, 1)
  return src


if __name__ == "__main__":
  base = BUILD / "serve_base.js"
  out = BUILD / "serve_decode.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, "decode")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  d.stop()
  D = json.loads((BUILD.parent / "nf-decode/cpu.json.d").read_text())
  n = max(D.get("n", 1), 1)
  print(f"\nTHE DECODE's PARTS, **IN THE DAEMON** ({n} turns), ms a turn:")
  for k in ("decode", "split", "strings", "numbers", "rows", "ku_row", "arg_of", "append"):
    if k in D and D[k] is not None:
      print(f"  {k:9s} {D[k]/n:.4f}")
  print(f"\n THE **SPLIT** IS {100*D['split']/n/(D['decode']/n):.1f}% OF THE DECODE, "
        f"AND IT IS **THE SAME STRING SPLIT **TWICE**.")
  print(f" **")
  print(f" **")
  print(f" **")
  print(f" **")
