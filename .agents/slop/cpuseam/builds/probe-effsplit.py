# PROBE: **THE WIRE's THREE EFFECTS, MEASURED IN THE DAEMON, ONE AT A TIME.**
#
# THE QUESTION: THE `numbers` CLOCK READS 0.49 ms A TURN AND THE PURE JS READS 0.187 ms.
# **THE 0.30 ms GAP IS THE BEND SIDE.** BUT WHICH BEND SIDE? THE `Wire.numbers` EFFECT's
# CONTINUATION IS `kus_io_c3` -- AND **THE CONTINUATION RUNS THE WHOLE ROW WALK** (`kus_rows_go`),
# BECAUSE THE EFFECT's RESULT IS THE LIST AND THE WALK IS THE **NEXT** EFFECT IN THE CHAIN.
#
# **SO THE `numbers` CLOCK MAY BE MEASURING THE ROW WALK TOO.** THIS PROBE PUTS A CLOCK
# **AROUND THE EFFECT'S OWN JS BODY** AND **AROUND THE CONTINUATION** SEPARATELY, IN THE
# DAEMON, AND READS BOTH.
#
# THE PATCH SITES ARE **COUNTED BEFORE THEY ARE APPLIED**, SO A MISS IS AN ERROR.

import json
import os
import pathlib
import sys
import time

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import portc  # noqa: E402
import noisefloor  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"

ACC = ("globalThis.__D = globalThis.__D || {eff:0, cont:0, n:0};\n"
       "globalThis.__M = (k, t0) => { globalThis.__D[k] += (performance.now() - t0); };")

PATCHES = [
  # THE ACCUMULATOR.
  ("function $serve(_fuel_0, _m_0, _s_0) {", ACC + "\nfunction $serve(_fuel_0, _m_0, _s_0) {"),

  # **THE EFFECT's OWN JS BODY**: THE TIME FROM ENTERING `wire_numbers` TO ITS RETURN.
  # **ONLY `wire_numbers`** -- `wire_strings` IS A DIFFERENT FUNCTION WITH A DIFFERENT BODY,
  # AND THE TWO PATCH SITES MUST NOT OVERLAP.
  ("function wire_numbers(s) {\n  const parts = s.split(\" \");",
   "function wire_numbers(s) {\n  const __t0 = performance.now();\n  const parts = s.split(\" \");"),
  ("""    rows = { $: "Con", head: nums, tail: rows };
  }
  return rows;
}""",
   """    rows = { $: "Con", head: nums, tail: rows };
  }
  globalThis.__M("eff", __t0);
  return rows;
}"""),

  # THE DUMP.
  ("""    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);""",
   """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__D || {})); } catch (e) {} }
    globalThis.__D.n = (globalThis.__D.n || 0) + 1;
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
  out = BUILD / "serve_effsplit.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, "effsplit")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  d.stop()
  D = json.loads((BUILD.parent / "nf-effsplit/cpu.json.d").read_text())
  n = max(D.get("n", 1), 1)
  print(f"\nTHE EFFECT's OWN JS BODY, IN THE DAEMON ({n} turns):")
  print(f"  eff  {D['eff']/n:.4f} ms a turn   (BOTH EFFECTS, SO PER-CALL IT IS "
        f"{D['eff']/n/2:.4f})")
  print(f"\nAND THE PURE JS SAID 0.187 ms FOR `wire_numbers` ALONE.")
