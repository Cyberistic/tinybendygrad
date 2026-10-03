#!/usr/bin/env python3
"""dev-mutate.py -- measured mutation table for tinybendygrad/device.bend's
`device_usage` / `tag_of` block, so the nine `allow_*` rows are not decoration.

Every row printed is DIFFED WHOLE `name=value` LINES (agent-core: a name-comparing
harness reports 0 for every mutation). The live tree is NEVER written: the file is
mutated in a scratch COPY of `tinybendygrad/`, and the run aborts loudly if the
mutant prints zero rows -- bend stack-overflows ~1 run in 20 and a 0-row result is
indistinguishable from "not started".
"""
import difflib, os, re, shutil, subprocess, sys, tempfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(REPO, "bin", "bend")
SRC = os.path.join(REPO, "tinybendygrad")
REL = "device.bend"


def run(tree):
    p = subprocess.run([BEND, os.path.join(tree, REL)], capture_output=True, text=True, cwd=REPO)
    return p.stdout


MUTATIONS = [
    ("M1 `device_usage` does NOT canonicalize",
     "  allowed(allow, canon(ix))", "  allowed(allow, ix)"),
    ("M2 `canon.go` drops the head's `to_upper`",
     "    case h <> t: String.concat([String.to_upper(h), rest_of(t)])",
     "    case h <> t: String.concat([h, rest_of(t)])"),
    ("M3 `tag_of` lower-cases the allow-list head",
     'String.eq(h, "DISK"), 6,', 'String.eq(String.to_lower(h), "DISK"), 6,'),
    ("M4 `tag_of` never matches NPY",
     'String.eq(h, "NPY"), 10,', 'String.eq(h, "NPY_DISABLED"), 10,'),
    ("M5 `tag_of` never matches DISK",
     'String.eq(h, "DISK"), 6,', 'String.eq(h, "DISK_DISABLED"), 6,'),
    ("M6 `tag_of` never matches PYTHON",
     'String.eq(h, "PYTHON"), 13, 0', 'String.eq(h, "PYTHON_DISABLED"), 13, 0'),
]


def main():
    with tempfile.TemporaryDirectory() as tmp:
        tree = os.path.join(tmp, "tinybendygrad")
        shutil.copytree(SRC, tree)
        path = os.path.join(tree, REL)
        pristine = open(path).read()

        base = run(tree)
        if not base.strip():
            sys.exit("BASELINE PRINTED ZERO ROWS -- refusing to report a mutation table")
        nrows = sum(1 for ln in base.splitlines() if "=" in ln)
        print(f"baseline: {nrows} rows\n")
        print(f"{'mutation':46s} {'#':>3s}  rows moved")
        print("-" * 110)
        for name, old, new in MUTATIONS:
            if pristine.count(old) != 1:
                sys.exit(f"ABORT: {name!r}: pattern occurs {pristine.count(old)}x, need exactly 1")
            open(path, "w").write(pristine.replace(old, new))
            got = run(tree)
            if not got.strip():
                sys.exit(f"ABORT: {name!r} printed ZERO rows (stack overflow?) -- not a zero")
            moved = [ln.split("=", 1)[0] for ln in difflib.unified_diff(
                base.splitlines(), got.splitlines(), n=0, lineterm="")
                if ln.startswith("-") and not ln.startswith("---")]
            print(f"{name:46s} {len(moved):3d}  {', '.join(moved) or '(none)'}")
            open(path, "w").write(pristine)

        final = run(tree)
        if final != base:
            sys.exit("ABORT: scratch file did not restore")
        print("\nscratch restored; baseline reproduced")


if __name__ == "__main__":
    main()