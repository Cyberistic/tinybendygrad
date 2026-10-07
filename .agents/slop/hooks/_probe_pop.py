import importlib.util, sys
from pathlib import Path
ROOT = Path(".").resolve()
p = ROOT / "gates" / "gates-pop.py"
spec = importlib.util.spec_from_file_location("gatespop_probe", p)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
entries, libs = m.discover(ROOT)
print(f"HOMES={m.HOMES}  entries={len(entries)}  libs={len(libs)}")
from collections import Counter
print("entry_reason counts:", Counter(m.entry_reason(e) for e in entries))
print("libs suffix:", Counter(e.suffix for e in libs))
print("--- entry files ---")
for e in entries: print("  ", e.relative_to(ROOT))
