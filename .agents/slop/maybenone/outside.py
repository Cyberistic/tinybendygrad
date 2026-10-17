#!/usr/bin/env python3
r"""The census set is `os.walk` over the DERIVED gate homes.  What exit sites does that walk
not reach?  Split by top-level owner, and by whether git tracks the file -- an untracked
scratch file is not a hole in a gate, a tracked one is."""
import ast, importlib.util, os, subprocess, sys
from collections import Counter
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
def load(n, p):
    s = importlib.util.spec_from_file_location(n, p); m = importlib.util.module_from_spec(s)
    sys.modules[n] = m; s.loader.exec_module(m); return m
ec = load("ec", ROOT / "gates" / "exitcode-census-gate.py"); pop = load("ecp", ROOT / "gates" / "gates-pop.py")
homes, _ = pop.gate_homes(ROOT)
W = set()
for h in homes:
    for dp, dn, fn in os.walk(ROOT / h):
        dn[:] = [d for d in dn if d != "__pycache__"]
        W |= {str((Path(dp) / n).resolve()) for n in fn if n.endswith(".py")}
tracked = set(subprocess.run(["git", "ls-files", "-z"], capture_output=True, text=True,
                             cwd=ROOT).stdout.split("\0"))
files = Counter(); sites = Counter(); tsites = Counter(); tfiles = Counter()
not_chosen = Counter()
for dp, dn, fn in os.walk(ROOT):
    dn[:] = [d for d in dn if d not in (".git", "__pycache__", "node_modules", "references", "runs")]
    for n in fn:
        if not n.endswith(".py"): continue
        p = (Path(dp) / n).resolve()
        if str(p) in W: continue
        try: tree = ast.parse(p.read_text(errors="replace"))
        except Exception: continue
        s = ec.extract(tree)
        if not s: continue
        top = p.relative_to(ROOT).parts[0]
        files[top] += 1; sites[top] += len(s)
        if str(p.relative_to(ROOT)) in tracked:
            tfiles[top] += 1; tsites[top] += len(s)
            env = {"gatekit": load("gk", ROOT/"gates"/"gatekit.py"), "funcs": {}, "ints": {}, "delegated": set()}
            funcs = {f.name: f for f in ast.walk(tree) if isinstance(f, (ast.FunctionDef, ast.AsyncFunctionDef))}
            env.update(funcs=funcs, ints=ec.module_ints(tree), delegated=ec.own_exits(tree))
            for _l, v in s:
                if ec.classify_site(v, tree, env)[0] not in ec.CHOSEN:
                    not_chosen[f"{top}/{n}"] += 1
print(f"W (census set) = {len(W)} files\n")
print(f"{'top-level owner':<26} {'files':>7} {'sites':>7} {'TRACKED files':>15} {'TRACKED sites':>14}")
for top, c in files.most_common():
    print(f"{top:<26} {c:>7} {sites[top]:>7} {tfiles.get(top,0):>15} {tsites.get(top,0):>14}")
print(f"{'TOTAL':<26} {sum(files.values()):>7} {sum(sites.values()):>7} {sum(tfiles.values()):>15} {sum(tsites.values()):>14}")
print(f"\nNOT-CHOSEN shapes among TRACKED .py OUTSIDE the census set: {sum(not_chosen.values())} sites in {len(not_chosen)} files")
for k, v in sorted(not_chosen.items(), key=lambda kv: -kv[1])[:20]: print(f"   {k:<52} {v}")
