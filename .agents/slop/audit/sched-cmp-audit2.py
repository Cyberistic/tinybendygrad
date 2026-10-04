#!/usr/bin/env python3
"""sched-cmp-audit2.py -- the PORT-side plant and the literal-denominator plant.

PLANT 2  mutate the PORT (a full COPY of tinybendygrad in $TMPDIR), regenerate the
         snapshot from the copy, and ask whether `sched-cmp.py` -- run as
         committed, from the live tree -- can see it.
PLANT 3  add a SEVENTH spec so the header's hardcoded `specs_attempted=6` and the
         hardcoded `6 specs` in the denominator line are both falsifiable.

The layout that works: `$TMPDIR/p2root/.agents/slop/sched-fixture.bend` +
`$TMPDIR/p2root/tinybendygrad/...`, because the fixture's imports are
`./../../tinybendygrad/...`. Measured: a flat copy of the fixture into $TMPDIR
cannot resolve them and bend prints `SOME PROOFS FAIL` with 0 rows -- which is
exactly the trap in agent-core.md about `$TMPDIR` scratch copies.
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
SLOP = os.path.join(REPO, ".agents/slop")
BEND = os.path.join(REPO, "bin/bend")
TMP = os.path.join(tempfile.gettempdir(), "schedaudit2")
PUBLISHED = "207ee494251e3dcde90ef2b03e5709899ff39604885b7bedad06b3beadd34817"


def sha(ls):
    return hashlib.sha256("\n".join(l for l in ls if l.strip()).encode()).hexdigest()


def emit(fixture, cwd):
    r = subprocess.run([BEND, fixture], cwd=cwd, capture_output=True, text=True,
                       timeout=3600)
    return [l for l in r.stdout.splitlines() if l.strip()], r.returncode, r.stderr


def run_cmp(harness_dir):
    env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
    env["LC_ALL"] = "C"; env["DEV"] = "NONE"
    r = subprocess.run([sys.executable, os.path.join(harness_dir, "sched-cmp.py")],
                       cwd=REPO, capture_output=True, text=True, env=env, timeout=1800)
    out = [l for l in r.stdout.splitlines() if l.startswith("#")
           or l.startswith("DISAGREE") or l.startswith("PORT_ONLY")]
    return out, r.returncode


def build_root(name):
    root = os.path.join(TMP, name)
    shutil.rmtree(root, ignore_errors=True)
    os.makedirs(os.path.join(root, ".agents/slop"))
    shutil.copytree(os.path.join(REPO, "tinybendygrad"),
                    os.path.join(root, "tinybendygrad"), symlinks=False)
    shutil.copy(os.path.join(SLOP, "sched-fixture.bend"),
                os.path.join(root, ".agents/slop/sched-fixture.bend"))
    return root


if __name__ == "__main__":
    print("=" * 78)
    print("PLANT 2 -- FIDELITY FIRST: an unmutated $TMPDIR copy must reproduce the")
    print("           published snapshot sha, or the copy pipeline is not sound.")
    root = build_root("clean")
    rows, rc, err = emit(os.path.join(root, ".agents/slop/sched-fixture.bend"), root)
    print(f"  bend on the clean copy: rc={rc} rows={len(rows)}")
    print(f"  sha={sha(rows)}")
    print(f"  == sha published in sched-stage2.md? {sha(rows) == PUBLISHED}")
    if err.strip():
        print("  stderr:", err.strip().splitlines()[0])
    print(f"  == live tree's sched-port.txt?  "
          f"{sha(rows) == sha([l for l in open(os.path.join(SLOP,'sched-port.txt')).read().splitlines()])}")

    print("\n" + "=" * 78)
    print("PLANT 2 -- MUTATE THE PORT IN THE COPY: `Lin.out` drops its first src.")
    root2 = build_root("planted")
    sc = os.path.join(root2, "tinybendygrad/schedule/__init__.bend")
    t = open(sc).read()
    old = "def Lin.out(x: Lin) -> List<&2, U32>:\n  match x:\n    case Lin{ar, c, out}: out\n"
    assert t.count(old) == 1, "Lin.out body not located verbatim"
    new = ("def Lin.out(x: Lin) -> List<&2, U32>:\n  match x:\n"
           "    case Lin{ar, c, out}: List.drop(&2, U32, out, 1n)\n")
    open(sc, "w").write(t.replace(old, new))
    print(f"  mutated {os.path.relpath(sc, root2)} -- Lin.out drops 1 src")
    rows2, rc2, err2 = emit(os.path.join(root2, ".agents/slop/sched-fixture.bend"), root2)
    print(f"  bend on the PLANTED copy: rc={rc2} rows={len(rows2)}")
    print(f"  sha={sha(rows2)}   differs from clean? {sha(rows2) != sha(rows)}")
    if err2.strip():
        print("  stderr:", err2.strip().splitlines()[0])

    print("\n  NOW THE QUESTION: does the COMMITTED comparator see any of this?")
    out, crc = run_cmp(SLOP)
    for l in out:
        if l.startswith("DISAGREE") or l.startswith("PORT_ONLY") or "fields_agree" in l:
            print("   ", l)
    print(f"    rc={crc}")
    planted_rows = len(rows2) if rows2 else 0
    print(f"    rows the planted port produces: {planted_rows};"
          f" rows the committed comparator read: 60")
    print("    ^ sched-cmp.py reads ONLY sched-port.txt. It spawns no process and")
    print("      never touches tinybendygrad/. A port edit CANNOT move this number")

    # feed the planted snapshot in, to show the comparison itself is not the issue
    hd = os.path.join(TMP, "harness-planted")
    shutil.rmtree(hd, ignore_errors=True)
    os.makedirs(hd)
    for f in ("sched-cmp.py", "sched-oracle.py"):
        shutil.copy(os.path.join(SLOP, f), os.path.join(hd, f))
    open(os.path.join(hd, "sched-port.txt"), "w").write("\n".join(rows2) + "\n")
    out2, crc2 = run_cmp(hd)
    print("\n  With the PLANTED snapshot fed in by hand:")
    for l in out2:
        if l.startswith("DISAGREE") or l.startswith("PORT_ONLY") or "fields_agree" in l:
            print("   ", l[:160])
    print(f"    rc={crc2}")

    # ------------------------------------------------------------------ PLANT 3
    print("\n" + "=" * 78)
    print("PLANT 3 -- the denominator's '6 specs' and 'specs_attempted=6' are LITERALS")
    hd3 = os.path.join(TMP, "harness-7specs")
    shutil.rmtree(hd3, ignore_errors=True)
    os.makedirs(hd3)
    for f in ("sched-cmp.py", "sched-oracle.py"):
        shutil.copy(os.path.join(SLOP, f), os.path.join(hd3, f))
    # append a SEVENTH spec that reuses s_chain, and give it the chain's ten rows
    so = os.path.join(hd3, "sched-oracle.py")
    t = open(so).read()
    old3 = '  ("chain", s_chain),\n]'
    assert t.count(old3) == 1, "SPECS tail not located verbatim"
    open(so, "w").write(t.replace(old3, '  ("chain", s_chain),\n  ("seventh", s_chain),\n]'))
    base = [l for l in open(os.path.join(SLOP, "sched-port.txt")).read().splitlines() if "=" in l]
    extra = [re.sub(r"^chain_", "seventh_", l) for l in base if l.startswith("chain_")]
    open(os.path.join(hd3, "sched-port.txt"), "w").write("\n".join(base + extra) + "\n")
    out3, crc3 = run_cmp(hd3)
    for l in out3[:2]:
        print("   ", l)
    print(f"    rc={crc3}")
    print("    ^ 70 fields were compared from SEVEN specs, and the header still says")
    print("      'specs_attempted=6 specs_scheduled=6', and the denominator still says")
    print("      '6 specs x 11 fields' -- which is 66, not 70.")