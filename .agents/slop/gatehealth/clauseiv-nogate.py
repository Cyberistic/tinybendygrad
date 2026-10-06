#!/usr/bin/env python3
"""Does clause IV's UNMEASURABLE branch charge anything to rc? Drive report() directly
with two families that both have healthy=None, on an empty scratch dir, so I/II/III/V
are all green and the ONLY thing speaking is clause IV's continue."""
import importlib.util
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[3]
HERE = pathlib.Path(__file__).resolve().parent

spec = importlib.util.spec_from_file_location("rcmod", ROOT / "gates" / "retention-check.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

clean = HERE / "clean"
clean.mkdir(parents=True, exist_ok=True)
for p in clean.iterdir():
    p.unlink()

outs = [
    m.Output("graphcmp", str(clean), "gates/gatekit.py", {"x"}, None),
    m.Output("gates", str(clean), "gates/gatekit.py", m.GATEKIT_OUTPUT, None),
]
rc = m.report(outs)
print(f"report() returned {rc}  (0 => clause IV's two UNMEASURABLEs did NOT gate)")
