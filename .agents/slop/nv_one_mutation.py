#!/usr/bin/env python3
"""nv_one_mutation.py -- run ONE entry of nv_mutate.py's MUTATIONS against the
digest-asserted staged mirror and print the rows it moved BY NAME, in full.

It exists because `nv_mutate.py` prints only the first three moved rows and ABORTS
the table when a mutant produces no output at all -- and the run that found the
BOOT_42 transposition died at entry [19] before it could print a full list. A
mutation that moves 22 rows and reports 3 of them is a table that cannot be read.

Nothing here writes the live tree: `staged_mut.Staged` stages `jj file show -r @`
BESIDE the file (so `./ip.bend` still resolves), asserts sha256(mirror) ==
sha256(live) on entry, unlinks the staged copy in a finally, and REPORTS a live
digest that moved during the run.

usage: python3 .agents/slop/nv_one_mutation.py <index> [index ...]
"""
import ast, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import staged_mut as SM

ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "tinybendygrad/runtime/support/nv/nvdev.bend")


def mutations():
    tree = ast.parse(open(os.path.join(HERE, "nv_mutate.py")).read())
    for node in tree.body:
        if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", "") == "MUTATIONS":
            return ast.literal_eval(node.value)
    raise SystemExit("nv_mutate.py has no MUTATIONS")


def main():
    want = [int(a) for a in sys.argv[1:]]
    muts = mutations()
    out = []
    with SM.Staged(SRC, "nv1") as unit:
        original = unit.origin()
        base = unit.rows()
        SM.control(base, unit.rows(), "nvdev baseline (no edit)")
        print(f"baseline: {len(base)} name= rows, row-set digest {SM.row_digest(base)[:16]}\n")
        for i in want:
            label, find, repl, why = muts[i]
            print(f"[{i}] {label} -- {why}")
            if find not in original:
                print("    PATCH-NOT-APPLY: the anchor is not in the file\n")
                out.append(f"| {label} | PATCH-NOT-APPLY | |")
                continue
            unit.write(original.replace(find, repl, 1))
            t = unit.try_rows()
            unit.write(original)
            if t is None:
                err = " | ".join(l.strip() for l in (unit.stderr or "").splitlines()
                                 if l.startswith(("Error:", "- ", "Location:")))
                print(f"    NOT-A-PROGRAM after 5 attempts: {err[:300]}\n")
                out.append(f"| {label} | NOT-A-PROGRAM | |")
                continue
            m = sorted(k for k in set(base) | set(t) if base.get(k) != t.get(k))
            print(f"    {len(m)} rows moved:")
            for k in m:
                print(f"      {k}\n          was  {base.get(k, '<absent>')}\n          now  {t.get(k, '<absent>')}")
            out.append(f"| {label} | {len(m)} | {','.join(m)} |")
            print()
    with open(os.path.join(HERE, "nv_one_mutation.txt"), "w") as fh:
        fh.write("# nv_one_mutation.py -- MEASURED, one entry per requested index.\n")
        fh.write("\n".join(out) + "\n")
    return 0


sys.exit(main())