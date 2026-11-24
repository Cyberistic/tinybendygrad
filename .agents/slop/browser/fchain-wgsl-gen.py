#!/usr/bin/env python3
"""fchain-wgsl-gen.py -- the artifacts both lanes run, from two MEASURED sources.

  in:  fchain-wgsl.rows  -- the four modules the PORT's WGSL lane rendered (`fchainwgsl.bend`)
       fchain-ref.rows   -- the reference chain as u32 bit patterns (`fchain-harness --dump`)
  out: web/fchain-seed.json     {wiring, seed}          SERVED   (inputs only)
       web/fchain-modules.json  {modules}               SERVED   (the pre-rendered lane)
       fchain-want.json         {want}                  NOT SERVED -- it sits outside `web/`, so
                                                                  "the page never sees the oracle"
                                                                  is a filesystem fact, not a promise.

THE WIRING IS NOT INVENTED HERE EITHER: the per-kernel buffer order is `fchain-harness.c`'s own
`k0(a1,x,w1); k1(a2,a1); k2(a3,a2); k3(aout,a3,w2);` -- the same call order the C lane executes.
"""
import json, pathlib, re

HERE = pathlib.Path(__file__).resolve().parent
rows = (HERE / "fchain-wgsl.rows").read_text().split("chain_w=", 1)[1]
mods = [p.split("\n", 1)[1] for p in rows.split("--w") if p.strip()]

# THE FILE ALSO HOLDS THE HARNESS's OWN CHECK ROWS (`conv: OK  max-abs-diff=0.000e+00`), whose
# right-hand side is a float and not a word list, so a row is taken only when it IS a word list.
WORD_ROWS = re.compile(r"^([a-z0-9]+)=([0-9a-f]{8}(?:,[0-9a-f]{8})*)$")
ref = {}
for line in (HERE / "fchain-ref.rows").read_text().split("\n"):
    m = WORD_ROWS.match(line.strip())
    if m:
        ref[m.group(1)] = [int(x, 16) for x in m.group(2).split(",")]

WIRING = [["h1", "x", "w1"], ["h2", "h1"], ["h3", "h2"], ["out", "h3", "w2"]]
(HERE / "web").mkdir(exist_ok=True)
(HERE / "web" / "fchain-seed.json").write_text(json.dumps(
    {"wiring": WIRING, "seed": {k: ref[k] for k in ("x", "w1", "w2")}}))
(HERE / "web" / "fchain-modules.json").write_text(json.dumps({"modules": mods}))
(HERE / "fchain-want.json").write_text(json.dumps({"want": {k: ref[k] for k in ("h1", "h2", "h3", "out")}}))
print(f"modules={len(mods)} wiring={len(WIRING)} "
      f"seed={ {k: len(v) for k, v in ref.items() if k in ('x','w1','w2')} } "
      f"want={ {k: len(ref[k]) for k in ('h1','h2','h3','out')} }")
