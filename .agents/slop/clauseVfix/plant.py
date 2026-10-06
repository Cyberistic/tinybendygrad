#!/usr/bin/env python3
"""PLANT: an `add --intent-to-add` placeholder is EMPTY in the index and ABSENT from HEAD.

Runs the plant, measures BOTH algorithms against the SAME planted state, then removes the
plant and asserts the tree is restored for that path. Nothing else in the index is touched.
"""
import importlib.util
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GIT_EMPTY_BLOB = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"
TARGET = ROOT / ".agents/slop/canrun/PLANT.intent-to-add.rows"
REL = str(TARGET.relative_to(ROOT))
DIR = os.path.dirname(REL)


def git(*args):
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def load_gendirs():
    p = ROOT / "gates" / "gendirs.py"
    spec = importlib.util.spec_from_file_location("gendirs", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def old_tracked_dirs():
    """Pre-repair algorithm: ls-files -s, compare SHA field (the index)."""
    _, out, _ = git("ls-files", "-s")
    ent, emp = {}, {}
    for line in out.splitlines():
        meta, _, path = line.partition("\t")
        parts = meta.split()
        if len(parts) < 2:
            continue
        d = os.path.dirname(path)
        ent[d] = ent.get(d, 0) + 1
        if parts[1] == GIT_EMPTY_BLOB:
            emp[d] = emp.get(d, 0) + 1
    return ent, emp


def snap(g):
    ent, emp = old_tracked_dirs()
    new_all, new_empty = g.tracked_dirs()
    return {
        "OLD/index entries": ent.get(DIR, 0),
        "OLD/index empty": emp.get(DIR, 0),
        "NEW/HEAD entries": new_all.get(DIR, 0),
        "NEW/HEAD empty": new_empty.get(DIR, 0),
    }


def show(label, s):
    print(f"  {label:12} " + "  ".join(f"{k}={v}" for k, v in s.items()))


def main():
    g = load_gendirs()
    rc = 0
    print(f"target: {REL}\n")

    print("1) BEFORE plant")
    before = snap(g)
    show("before", before)

    print("\n2) PLANT: 11 bytes on disk, `git add --intent-to-add`")
    TARGET.write_bytes(b"11 bytes!\n")
    c, _, e = git("add", "--intent-to-add", "--", REL)
    assert c == 0, e
    _, porc, _ = git("status", "--porcelain=v2", "--", REL)
    print(f"  git status --porcelain=v2: {porc.strip()!r}")
    print(f"  on disk: {TARGET.stat().st_size} bytes   "
          f"index blob: {git('ls-files', '-s', '--', REL)[1].split()[1]}")

    print("\n3) MEASURE under the planted state")
    planted = snap(g)
    show("planted", planted)

    print("\n4) ASSERTIONS")
    checks = [
        ("OLD counts the placeholder as a tracked entry",
         planted["OLD/index entries"] == before["OLD/index entries"] + 1),
        ("OLD counts it at git's EMPTY BLOB",
         planted["OLD/index empty"] == before["OLD/index empty"] + 1),
        ("NEW does NOT add an entry (it is not in HEAD)",
         planted["NEW/HEAD entries"] == before["NEW/HEAD entries"]),
        ("NEW does NOT count it empty",
         planted["NEW/HEAD empty"] == before["NEW/HEAD empty"]),
    ]
    for name, ok in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}")
        rc |= 0 if ok else 1

    print("\n5) UNSTAGE and remove")
    git("reset", "-q", "--", REL)
    TARGET.unlink()

    print("\n6) RESTORE PROOF")
    _, ls, _ = git("ls-files", "--", REL)
    _, dc, _ = git("diff", "--cached", "--", REL)
    _, st, _ = git("status", "--porcelain", "--", REL)
    _, n, _ = git("ls-files", "--stage")
    print(f"  git ls-files -- {REL}       -> {ls!r} (want empty)")
    print(f"  git diff --cached -- {REL}  -> {dc!r} (want empty)")
    print(f"  git status --porcelain      -> {st!r} (want empty)")
    print(f"  index empty-blob entries now: "
          f"{sum(1 for l in n.splitlines() if l.split()[1] == GIT_EMPTY_BLOB)}")
    restored = not ls and not dc and not st
    print(f"  {'PASS' if restored else 'FAIL'}  tree restored for {REL}")
    rc |= 0 if restored else 1

    print(f"\nPLANT: {'GREEN' if rc == 0 else 'RED'}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
