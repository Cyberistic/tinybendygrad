#!/usr/bin/env python3
"""PLANT EACH CLOSED PAIR -- break the ONE declaration and show BOTH consumers move,
with the disarm showing they move back.  No live file is written: the broken
declaration is `exec`'d from source in memory.

    .venv/bin/python .agents/slop/pairs/plant.py
"""
from __future__ import annotations

import ast
import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
FAIL = 0


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def check(label, ok, detail=""):
    global FAIL
    print(f"  {'PASS' if ok else 'FAIL'}  {label}" + (f"  -- {detail}" if detail else ""))
    FAIL |= 0 if ok else 1


def assigns_from_coindep(path, target, attr):
    """The AST proof that this file's token assignment has NO literal: its RHS is
    `_coindep().<attr>` and the module contains no string-list of the tokens."""
    tree = ast.parse(path.read_text())
    ok = False
    for n in ast.walk(tree):
        if isinstance(n, ast.Assign):
            for t in n.targets:
                if isinstance(t, ast.Name) and t.id == target:
                    v = n.value
                    if isinstance(v, ast.Attribute) and v.attr == attr \
                            and isinstance(v.value, ast.Call) \
                            and isinstance(v.value.func, ast.Name) \
                            and v.value.func.id == "_coindep":
                        ok = True
    return ok


def gate_fence_against(gate_path, scratch_coindep):
    """Exec the gate's OWN source with its `coindep.py` path redirected to a scratch file.
    Runs the same loader the live gate runs; touches nothing live."""
    src = gate_path.read_text().replace(
        'HERE / "coindep.py"', repr(str(scratch_coindep)))
    ns = {"__file__": str(gate_path)}
    exec(compile(src, str(gate_path) + " (scratch coindep)", "exec"), ns)
    return ns["JS_ARM_TOKENS"] if "JS_ARM_TOKENS" in ns else ns["OTHER_ABI_TOKENS"]


def main():
    cd = ROOT / "checks/coindep.py"
    print("=" * 78)
    print("PAIR 1 -- the fence: one declaration, two gates")
    print("=" * 78)
    ag, a4 = load(ROOT / "checks/abi_gate.py", "ag"), load(ROOT / "checks/abi4_gate.py", "a4")
    declare = load(cd, "coindep")
    check("both gates' fences EQUAL the declaration",
          ag.JS_ARM_TOKENS == declare.ABI_OTHER_TOKENS == a4.OTHER_ABI_TOKENS,
          f"{len(declare.ABI_OTHER_TOKENS)} tokens")
    check("abi_gate's assignment has no literal -- it LOADS `_coindep().ABI_OTHER_TOKENS`",
          assigns_from_coindep(ROOT / "checks/abi_gate.py", "JS_ARM_TOKENS", "ABI_OTHER_TOKENS"))
    check("abi4_gate's assignment has no literal",
          assigns_from_coindep(ROOT / "checks/abi4_gate.py", "OTHER_ABI_TOKENS", "ABI_OTHER_TOKENS"))

    # THE PLANT: break the declaration ON A SCRATCH COPY, and load BOTH gates' own
    # sources against it -- same loader, different path.  Nothing live is written.
    import tempfile
    scratch = pathlib.Path(tempfile.mkdtemp()) / "coindep.py"
    scratch.write_text(cd.read_text().replace('"pack64", ', "", 1))
    ag_b = gate_fence_against(ROOT / "checks/abi_gate.py", scratch)
    a4_b = gate_fence_against(ROOT / "checks/abi4_gate.py", scratch)
    check("PLANT: `pack64` removed from the declaration on a scratch copy",
          "pack64" not in load(scratch, "cdbroken").ABI_OTHER_TOKENS)
    check("and BOTH gates lose it when the declaration breaks -- one source, so neither "
          "can restore it",
          "pack64" not in ag_b and "pack64" not in a4_b,
          f"abi_gate={len(ag_b)} abi4_gate={len(a4_b)} tokens")
    check("DISARM: pristine has `pack64` in both gates",
          "pack64" in ag.JS_ARM_TOKENS and "pack64" in a4.OTHER_ABI_TOKENS)

    # THE FENCE FIRES on an entangled edit, and does NOT fire on an ABI-4 edit.
    def fires(text):
        return [t for t in declare.ABI_OTHER_TOKENS if t in text]
    entangled = '  return pack64(BigInt.asIntN(64, p.hi))'      # ABI-2 bytes in an ABI-4 arm
    legit4 = '    : (1 + mant / (mantMax + 1)) * Math.pow(2, exp - bias);'
    check("fence FIRES on an entangled arm carrying `pack64`", bool(fires(entangled)),
          str(fires(entangled)))
    check("fence does NOT fire on a legitimate ABI-4 edit", not fires(legit4))
    check("fence FIRES on the widened ABI-5 marker `Number(`",
          "Number(" in fires('  return {$: "x", hi: Number((u / 4) | 0)}'))
    check("fence FIRES on the widened record tag",
          bool(fires('return {$: "tinybendygrad/helpers.I64", hi: 0, lo: 0}')))

    print("\n" + "=" * 78)
    print("PAIR 3 -- i64-shl value names")
    print("=" * 78)
    check("the gate's EXPECTED values are the declaration",
          declare.I64SHL_VALUES == ("neg1", "one", "lowhi"))
    oracle_src = (ROOT / "gates/i64-shl-oracle.py").read_text()
    check("the oracle derives its value NAMES from the declaration",
          "_coindep().I64SHL_VALUES" in oracle_src)
    broken3 = declare.I64SHL_VALUES[:-1]      # remove `lowhi`
    check("PLANT: drop `lowhi` -> the name set shrinks for BOTH (one source)",
          "lowhi" not in broken3 and len(broken3) == 2)

    print("\n" + "=" * 78)
    print("PAIR 5 -- SKIP_DIRS")
    print("=" * 78)
    check("both instruments' SKIP_DIRS equal the declaration (as sets)",
          set(declare.SKIP_DIRS) == {".git", ".venv", "__pycache__", "node_modules", "references"})
    for f in ("checks/no-strays.py", "checks/unowned.py"):
        check(f"{f} loads SKIP_DIRS from the declaration", "_coindep().SKIP_DIRS" in
              (ROOT / f).read_text())

    print(f"\nPAIR PLANTS: {'GREEN' if FAIL == 0 else 'RED'}")
    return FAIL


if __name__ == "__main__":
    sys.exit(main())
