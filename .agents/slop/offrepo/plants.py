#!/usr/bin/env python3
"""THE TWO COLUMNS, PER FILE, ON THE REAL FILES.

    COLUMN 1  CORRECT ROOT STILL PASSES -- the file, in place, must NOT refuse on its ROOT.
    COLUMN 2  MOVED TREE GOES RED NAMING THE DIRECTORY IT REACHED -- a copy one directory
              DEEPER must refuse with `is not the repo root` AND print the directory it landed on.

WHY COLUMN 1 IS NOT "EXIT 0". MEASURED, twice today, in opposite directions: `lint_demo.sh` did
not refuse on the first plant because `${0:A:h:h}` collapsed to a string the marker test never
saw, and `e2esh`'s first cut asserted `$ROOT` and reported DID NOT REFUSE for a CORRECT refusal,
because the refusal exits BEFORE it can print. So the only honest column 1 is a DISCRIMINATOR ON
THE MESSAGE -- "did it refuse because the ROOT was wrong", which is a different question from "did
it run", and a gate that refuses on a swept input (rc 3, naming the input) has a CORRECT ROOT.

WHY THE MOVED COPY IS COPIED AND NOT SYMLINKED. `.resolve()` on both sides, or `/var` is compared
against `/private/var` and every root reads off-repo -- the belt's-own-fault failure, one symlink
and two spellings.

WHY THE PLANT DOES NOT RUN `bend`. `sz.bend` peaks 1,468 MB against a 2,048 MB ceiling and four
units are live. Every check here happens at IMPORT time, before any subprocess is spawned, so
nothing here can start a compiler. `plant()` therefore reads the root block only.

Writes `.agents/slop/offrepo/plants.tsv` and prints the table. Touches the live tree ONLY to read.
"""
import ast
import contextlib
import importlib.util
import io
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent / "plants.tsv"

TARGETS = [
    "checks/both-census.py",
    "checks/cl-port-gate.py",
    "checks/dup-census.py",
    "checks/gate.py",
    "checks/gate_norm.py",
    "checks/jsfix_gate.py",
    "checks/nl-gate-noguard.py",
    "checks/nl-gate.py",
    "checks/nvrows-deadrow-gate.py",
    "checks/oracle_f64.py",
    "checks/rn-gate.py",
]

ROOT_REFUSAL = "is not the repo root"

# Read the file's own root block by RUNNING its import, so the answer is the file's, not ours.
CHILD = '''
import contextlib, importlib.util, io, sys
spec = importlib.util.spec_from_file_location("_plant_target", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
buf = io.StringIO()
rc = 0
try:
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
        spec.loader.exec_module(mod)
except SystemExit as e:
    rc = e.code if isinstance(e.code, int) else 1
except BaseException as e:
    print("EXC " + type(e).__name__ + ": " + str(e).splitlines()[0][:90]); rc = 1
print("RC %d" % rc)
print("MSG " + buf.getvalue().strip().replace("\\n", " ")[:220])
sys.exit(0)
'''


def run(path):
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as fh:
        fh.write(CHILD)
        script = fh.name
    try:
        r = subprocess.run([sys.executable, script, str(path.resolve())],
                           capture_output=True, text=True, timeout=120)
    finally:
        Path(script).unlink()
    out = r.stdout.splitlines()
    rc = next((l[3:] for l in out if l.startswith("RC ")), "?")
    msg = next((l[4:] for l in out if l.startswith("MSG ")), "")
    exc = next((l[4:] for l in out if l.startswith("EXC ")), "")
    return rc, msg or exc


def markers(tree):
    """The two files whose PRESENCE is what `refuse()` tests, so a copy has them too."""
    (tree / "pyproject.toml").write_text("")
    (tree / "tinybendygrad").mkdir()


def col1(path):
    """In place: the ROOT refusal must not be what fired."""
    rc, msg = run(path)
    root_bad = ROOT_REFUSAL in msg
    return (not root_bad), rc, msg


def col2(path):
    """A copy one directory deeper. Two ways, because one belt is not enough:

    WAY A -- the copy is MOVED, keeping every sibling the file might read. A moved file that
            loses its inputs would refuse for the WRONG reason and look like a pass.
    WAY B -- a BARE copy in an empty tree that has only the two markers. Same file, same depth
            arithmetic, no siblings to be mistaken for the cause.
    """
    with tempfile.TemporaryDirectory() as td:
        deep = Path(td).resolve() / "deeper"
        deep.mkdir()
        shutil.copytree(path.parent, deep / path.parent.name)
        a_root = str(deep.resolve())
        a_rc, a_msg = run(deep / path.parent.name / path.name)
    with tempfile.TemporaryDirectory() as td:
        tree = Path(td).resolve()
        markers(tree)
        # THE COPY SITS ONE LEVEL DEEPER THAN ITS MARKERS. The markers are at the tree root
        # ONLY, so `parents[1]` from `deeper/checks/<f>` names `deeper/`, which holds neither --
        # and the ROOT refusal is what fires. The first version of this plant put the copy at
        # `checks/<f>` with the markers beside it, so `parents[1]` DID name the root, the root
        # check PASSED, and the refusal that came back was about an ABSENT INPUT: the plant was
        # measuring its own incompleteness. A plant that cannot make the subject wrong is a
        # plant that always passes.
        (tree / "deeper" / "checks").mkdir(parents=True)
        shutil.copy(path, tree / "deeper" / "checks" / path.name)
        b_root = str((tree / "deeper").resolve())
        b_rc, b_msg = run(tree / "deeper" / "checks" / path.name)
    return a_rc, a_msg, b_rc, b_msg, (a_root, b_root)


rows = ["file\tcol1_root_ok\tcol1_rc\tcol1_msg\tcol2A_red\tcol2A_rc\tcol2A_msg"
            "\tcol2B_red\tcol2B_rc\tcol2B_msg\treached_A\treached_B"]
allok = True
for t in TARGETS:
    p = ROOT / t
    ok1, rc1, msg1 = col1(p)
    a_rc, a_msg, b_rc, b_msg, (a_root, b_root) = col2(p)
    # COLUMN 2 must be a REFUSAL that (a) says the root is wrong, (b) PRINTS the directory it
    # reached, and (c) did not print the repo root. (b) is the load-bearing half and it is
    # asserted rather than assumed: a refusal that names nothing is a refusal a reader cannot
    # act on, which is the same failure as a README saying a file is missing without saying
    # which file.
    red_a = ROOT_REFUSAL in a_msg and a_root in a_msg and str(ROOT) not in a_msg
    red_b = ROOT_REFUSAL in b_msg and b_root in b_msg and str(ROOT) not in b_msg
    ok2 = red_a and red_b
    # A GATE THAT FAILS BOTH COLUMNS IS A GATE THAT ALWAYS FAILS, which is worse than not
    # fixing it, so it is called out by name rather than folded into a count.
    both_bad = (not ok1) and (not ok2)
    allok &= ok1 and ok2
    rows.append(f"{t}\t{int(ok1)}\t{rc1}\t{msg1[:70]}\t{int(red_a)}\t{a_rc}\t{a_msg[:70]}"
                f"\t{int(red_b)}\t{b_rc}\t{b_msg[:70]}\t{a_root}\t{b_root}")
    print(f"{t}")
    print(f"    COLUMN 1 correct root, in place : {'PASS' if ok1 else 'FAIL'}  rc={rc1}")
    print(f"      {msg1[:170]}")
    print(f"    COLUMN 2A copy one level deeper : {'RED ' if red_a else 'FAIL'}  rc={a_rc}")
    print(f"      {a_msg[:170]}")
    print(f"    COLUMN 2B bare copy, markers only: {'RED ' if red_b else 'FAIL'}  rc={b_rc}")
    print(f"      {b_msg[:170]}")
    if both_bad:
        print("    *** FAILS BOTH COLUMNS -- worse than leaving it alone ***")

OUT.write_text("\n".join(rows) + "\n")
print(f"\n{'ALL GREEN' if allok else 'RED'} -- wrote " + str(OUT.relative_to(ROOT)))