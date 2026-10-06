#!/usr/bin/env python3
"""Is `census()` byte-identical before/after removing the hand-list `skip`? Rebuild the OLD
`code_files` in memory and diff the two row sets. The population today is ONE file, so this is a
direct check that the hand list was inert on the current tree."""
import importlib.util, hashlib, json, os, pathlib, subprocess
ROOT = pathlib.Path(__file__).resolve().parents[3]
S = importlib.util.spec_from_file_location("census", ROOT / "checks/oracle-txt-census.py")

def load():
    m = importlib.util.module_from_spec(S); S.loader.exec_module(m); return m

def old_code_files(m):
    out = subprocess.run(["git","ls-files"], cwd=ROOT, capture_output=True, text=True).stdout.split()
    me = os.path.relpath(os.path.abspath(m.__file__), ROOT)
    skip = (me, ".agents/slop/oracles259/plants.py")
    return [ROOT / r for r in out if pathlib.Path(r).suffix in m.GATE_CODE
            and not r.startswith(("references/","tinygrad/",".agents/slop/oracletxt/"))
            and r not in skip]

m1 = load(); rows_new, _ = m1.census()
m2 = load(); m2.code_files = lambda: old_code_files(m2); rows_old, _ = m2.census()
n = json.dumps(rows_new, sort_keys=True); o = json.dumps(rows_old, sort_keys=True)
print(f"population rows: new={len(rows_new)} old={len(rows_old)}")
print(f"rows identical: {n == o}")
print(f"sha new {hashlib.sha256(n.encode()).hexdigest()[:16]}  old {hashlib.sha256(o.encode()).hexdigest()[:16]}")
