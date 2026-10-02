#!/usr/bin/env python3
"""rebase-portrows.py -- dump each port's own `name=value` row names, and the PREFIX
distribution. Prefixes are what a filename guess gets wrong: `hcq2.bend` prints `hq2_*`
and `ops_metal.bend` prints `om_*`, so the two are NOT interchangeable and the gate must
be wired by the prefix it can prove, not by the stem.
"""
import json, pathlib, sys
HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
import importlib.util
spec = importlib.util.spec_from_file_location("g", HERE / "rebase-gate.py")
G = importlib.util.module_from_spec(spec); spec.loader.exec_module(G)

plan = json.loads(G.sh("python3", ".agents/slop/rebase-plan.py", "--json").stdout)
srcs = next((b["files"] for b in plan["batches"] if b["id"] == int(sys.argv[1])), None) if len(sys.argv) > 1 \
       else [f for b in plan["batches"] for f in b["files"]]
ports = sorted({p for f in srcs for p in G.ports_of(f, plan)})
out = {}
for port in ports:
  bend = REPO / port
  if not bend.exists(): continue
  got = G.sh("./bin/bend", str(bend))
  r = G.rows(got.stdout)
  out[port] = {"rc": got.returncode, "rows": sorted(r), "prefixes": {}}
  import re, collections
  c = collections.Counter()
  for k in r:
    c[k.split("_")[0] if "_" in k else k] += 1
  out[port]["prefixes"] = dict(c.most_common(12))
  print(f"{port}\n   rc={got.returncode} rows={len(r)}  prefixes={out[port]['prefixes']}", flush=True)
  print(f"   sample: {sorted(r)[:8]}", flush=True)
(HERE / "rebase" / "portrows.json").write_text(json.dumps(out, indent=1))
