#!/usr/bin/env python3
"""PLANT AGAINST THE REAL CALLER: age one directory's newest file across the
60m window and show `checks/sweep.py`'s own verdict move -- twice, fresh process
each time so sweep's per-window cache is cold.

    fresh  : sweep says the probe dir is LIVE-UNIT
    aged   : sweep says the probe dir is no longer LIVE-UNIT (DOC, it is a .md)
    restore: sweep says LIVE-UNIT again

Run: .venv/bin/python .agents/slop/rosterwire/plant.py {fresh|aged|restore}
"""
import importlib.util, os, sys, time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
PROBE = os.path.join(ROOT, ".agents/slop/rosterwire/plantprobe")
REL = ".agents/slop/rosterwire/plantprobe/fresh.md"

def load():
    spec = importlib.util.spec_from_file_location("sweep", os.path.join(ROOT, "checks/sweep.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

def main():
    mode = sys.argv[1]
    os.makedirs(PROBE, exist_ok=True)
    p = os.path.join(PROBE, "fresh.md")
    open(p, "a").close()
    if mode == "aged":
        # age EVERY file under the top-level dir, or the newest one still counts
        old = time.time() - 3 * 3600
        for dp, _d, fs in os.walk(os.path.join(ROOT, ".agents/slop/rosterwire")):
            for f in fs:
                os.utime(os.path.join(dp, f), (old, old))
    else:
        os.utime(p, None)
    sweep = load()
    live = sweep.live_units(60)
    import types
    light = types.SimpleNamespace(root=ROOT, mentioned=set(), declared=set(),
                                  cites=[{}, {}], tracked=set())
    v = sweep.verdict_for(REL, set(), light)
    print(f"{mode:8s}  live_units(60m) names rosterwire: {'rosterwire' in live!s:5s}  "
          f"verdict_for({REL}) = {v}")

if __name__ == "__main__":
    main()
