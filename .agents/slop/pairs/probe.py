#!/usr/bin/env python3
"""coindependent pair-census, RE-TAKEN: the five named pairs, the 10th token, and the
tree-wide population -- all by DISCOVERY, none from the brief's list.

    .venv/bin/python .agents/slop/pairs/probe.py

Reads only; writes nothing live. `bend` is never run.
"""
from __future__ import annotations

import ast
import os
import pathlib
import re
import sys
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parents[3]          # .agents/slop/pairs -> repo
SKIP = {"__pycache__", "node_modules", ".venv", ".git", "references", "test", "tinygrad"}


def sources():
    for dp, dns, fns in os.walk(ROOT):
        dns[:] = sorted(d for d in dns if d not in SKIP)
        for f in sorted(fns):
            if f.endswith(".py"):
                yield pathlib.Path(dp) / f


# ---------------------------------------------------------------- A. the fence + 10th
def string_lists(p: pathlib.Path):
    try:
        tree = ast.parse(p.read_text(errors="replace"))
    except SyntaxError:
        return []
    out = []
    for n in ast.walk(tree):
        if isinstance(n, (ast.Tuple, ast.List, ast.Set)):
            vals, ok = [], True
            for e in n.elts:
                if isinstance(e, ast.Constant) and isinstance(e.value, str):
                    vals.append(e.value)
                else:
                    ok = False
                    break
            if ok and len(vals) >= 3:
                out.append((tuple(sorted(vals)), n.lineno, vals))
    return out


def fence_tokens(p: pathlib.Path, names) -> list[tuple[int, list[str]]]:
    """Every literal string-list whose NAME (`JS_ARM_TOKENS`/`OTHER_ABI_TOKENS`) we want."""
    src = p.read_text(errors="replace")
    tree = ast.parse(src)
    found = []
    for n in ast.walk(tree):
        if isinstance(n, ast.Assign) and isinstance(n.value, (ast.Tuple, ast.List)):
            for t in n.targets:
                if isinstance(t, ast.Name) and t.id in names:
                    vals = [e.value for e in n.value.elts
                            if isinstance(e, ast.Constant) and isinstance(e.value, str)]
                    found.append((n.lineno, vals))
    return found


def fence_analysis():
    print("=" * 78)
    print("PAIR 1 -- THE CONTENT FENCE: TWO GATES, ONE 9-TOKEN HAND LIST")
    print("=" * 78)
    ag = ROOT / "checks/abi_gate.py"
    a4 = ROOT / "checks/abi4_gate.py"
    cd = ROOT / "checks/coindep.py"
    # THE ORIGINAL 9, from the committed blob, so the finding is about the tree as found.
    import subprocess
    def blob_assign(path, name):
        src = subprocess.run(["git", "show", f"HEAD:{path.relative_to(ROOT)}"],
                             cwd=ROOT, capture_output=True, text=True).stdout
        tree = ast.parse(src)
        for n in ast.walk(tree):
            if isinstance(n, ast.Assign):
                for t in n.targets:
                    if isinstance(t, ast.Name) and t.id == name:
                        vals = [e.value for e in n.value.elts
                                if isinstance(e, ast.Constant)]
                        return n.lineno, vals
        return None, []
    agl, a = blob_assign(ag, "JS_ARM_TOKENS")
    a4l, b = blob_assign(a4, "OTHER_ABI_TOKENS")
    print(f"  AT HEAD -- abi_gate.py:{agl}   JS_ARM_TOKENS    = {a}")
    print(f"  AT HEAD -- abi4_gate.py:{a4l}  OTHER_ABI_TOKENS = {b}")
    print(f"  IDENTICAL: {a == b}   ({len(a)} strings each)  <- the two hand lists, the fault")
    # NOW: the literal is gone from BOTH; both read the one declaration.
    import importlib.util
    spec = importlib.util.spec_from_file_location("coindep", cd)
    dec = importlib.util.module_from_spec(spec); spec.loader.exec_module(dec)
    print(f"  NOW -- checks/coindep.py ABI_OTHER_TOKENS = {list(dec.ABI_OTHER_TOKENS)}")
    print(f"  the 9 literals still spelled in abi_gate.py? "
          f"{sum(t in ag.read_text() for t in a)} ; in abi4_gate.py? "
          f"{sum(t in a4.read_text() for t in a)}")

    # THE OTHER ABIS' VOCABULARY, DISCOVERED from the bytes the tree actually writes.
    # The ABI-2 arms live as literals in abi_gate.py; the ABI-2/3 lane lives in dtype.js.
    # We look for `<word>` and `<word> <number>n` tokens in that JS and in abi_gate's
    # ABI-2 constants, then ask which the fence does NOT contain.
    js = (ROOT / "tinybendygrad/runtime/dtype.js").read_text()
    abi = ag.read_text()
    # candidate tokens: JS field accesses, BigInt calls, shift-by-literal, io_tup, the tag.
    cand = set()
    cand |= set(re.findall(r"\bp\.\w+", js))                      # p.hi, p.lo, ...
    cand |= set(re.findall(r"\b(?:BigInt\.)?as[A-Z]\w+", js))     # asIntN, asUintN
    cand |= set(re.findall(r"(?:<<|>>|>>>)\s*\d+n", js))          # << 32n, >> 32n
    cand |= {t for t in re.findall(r"\b(io_tup|Number|BigInt)\b", js)}
    cand |= set(re.findall(r"\bthe following", js))               # (no-op)
    missing = sorted(t for t in cand if not any(t in f for f in a))
    present = sorted(t for t in cand if any(t in f for f in a))
    print(f"\n  ABI-2/3 JS vocabulary, discovered (dtype.js + abi_gate constants):")
    print(f"    covered by the fence : {present}")
    print(f"    NOT covered          : {missing}")

    # Is the fence's `>>> 32n` a token that exists anywhere in the tree?
    hits = grep_tree(">>> 32n")
    print(f"\n  the fence spells `>>> 32n`; occurrences outside the two fence lists:")
    print(f"    {[h for h in hits if 'abi_gate.py' not in h and 'abi4_gate.py' not in h]}")
    # Is the ABI-3 outbound shift `>> 32n` in the fence? It is cited as ABI-3's JS site.
    print(f"  `>> 32n` (abi.json ABI-3 js site, dtype.js:180, abi_gate.js constants): "
          f"in the fence? {any('>> 32n' in f for f in a)}")
    print(f"  `asUintN` (dtype.js:179 shipped): in the fence? "
          f"{any('asUintN' in f for f in a)}")
    return a, b, missing


def grep_tree(tok: str) -> list[str]:
    out = []
    for p in sources():
        try:
            for i, ln in enumerate(p.read_text(errors="replace").splitlines(), 1):
                if tok in ln:
                    out.append(f"{p.relative_to(ROOT)}:{i}")
        except OSError:
            pass
    return out


# ------------------------------------------------------- B. tree-wide, by DISCOVERY
def expectation_names(p: pathlib.Path) -> set[str]:
    try:
        tree = ast.parse(p.read_text(errors="replace"))
    except SyntaxError:
        return set()
    names = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.Compare):
            for op in n.ops or []:
                if isinstance(op, (ast.Eq, ast.NotEq, ast.In, ast.NotIn)):
                    for s in (n.left, *n.comparators):
                        if isinstance(s, ast.Name):
                            names.add(s.id)
        if isinstance(n, ast.Assert) and isinstance(n.test, ast.Name):
            names.add(n.test.id)
        if isinstance(n, ast.If) and isinstance(n.test, ast.Name):
            names.add(n.test.id)
    return names


def tree_sweep():
    print("\n" + "=" * 78)
    print("PAIR 5 -- THE POPULATION, BY os.walk (never the brief's five)")
    print("=" * 78)
    decls = defaultdict(list)
    exp = {}
    n = 0
    for p in sources():
        n += 1
        rel = str(p.relative_to(ROOT))
        exp[rel] = expectation_names(p)
        for key, line, _v in string_lists(p):
            decls[key].append((rel, line))
    shared = {k: v for k, v in decls.items()
              if len({r for r, _ in v}) >= 2 and len(k) >= 3}
    print(f"  {n} .py source files read (SKIP={sorted(SKIP)}); {len(decls)} string-list "
          f"declarations; {len(shared)} spelled in 2+ files")
    print("  A PAIR IS A CANDIDATE when >=1 site uses the shared list as an EXPECTATION:")
    cand = []
    for k, sites in sorted(shared.items(), key=lambda kv: -len(kv[1])):
        files = sorted({r for r, _ in sites})
        used = [r for r in files if exp.get(r)]
        cand.append((k, sites, used))
    print(f"\n  {len(cand)} shared literal lists; the brief named 5. FULL LIST:")
    for k, sites, used in cand:
        if len(k) < 4:
            continue
        print(f"\n  [{len(k)}] {list(k)[:6]}{' ...' if len(k) > 6 else ''}")
        for rel, line in sites:
            mark = "  <-- EXPECTATION" if exp.get(rel) else ""
            print(f"      {rel}:{line}{mark}")
    return cand


if __name__ == "__main__":
    fence_analysis()
    tree_sweep()
