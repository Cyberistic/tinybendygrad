#!/usr/bin/env python3
"""G8, AND WHY IT IS NOT A CLAUSE -- THREE MEASURED PARTS, NOT ONE ASSERTION.

`residue-internal-citer` asks "is this row named only from inside the residue?" The requested
refinement was G8: "IS THE CITER ITSELF A COPY?" -- a row named by an in-residue file that is
byte-identical to a file outside it is named by a copy, and a copy is not a witness.

MEASURED, ONCE, IN THREE PARTS:

  1. THE CLASS IS BIG. 200 rows at 60 minutes, 256 at 0, 27 at 1440. It is not a rounding error.
  2. G8'S DISARM DOES NOT MOVE IT. `Facts.copies = set()` -- one assignment, the map G8 reads --
     changes the count by **0** at all three windows. **A CLAUSE THAT IS INVARIANT UNDER THE CHANGE
     IT CLAIMS TO MEASURE IS NOT A CLAUSE.**
  3. THE REASON IS STRUCTURAL, AND IT IS GOOD NEWS. The corpus filter excludes byte-copies, so no
     copy is ever a citer and the question never arises. **THE RULE THAT DECIDED IT WAS THE CORPUS
     FILTER**, whose measured delta is 190 rows that stop being DELETE and 0 that become DELETE.

AND THE PART THAT EXPLAINS WHY NO PLANT CAN SAVE IT: `residue_copies()` reads `checks/residue.py`,
which does not exist in a synthetic tree, so it returns `set()` BY CONSTRUCTION. **A TEST THAT
CANNOT BE RUN IS NOT A TEST** -- and a synthetic tree here would measure a missing module. So the
plant below does NOT plant G8. It plants the two things that DO move, one row in and one row out.
"""
import collections, importlib.util, os, subprocess, sys, tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


sweep = load("sweep", os.path.join(ROOT, "checks/sweep.py"))
WINDOWS = (0, 60, 1440)
f = sweep.facts()


def g8_rows(fo, window):
    live = sweep.live_set(window, fo.root)
    n = 0
    for rel, _sz in fo.files:
        v = sweep.verdict_for(rel, fo.mentioned, fo)
        if rel in live and v not in ("PROTECTED", "LIVE-UNIT"):
            v = "LIVE"
        if v.startswith(f"{sweep.UNKNOWN}:residue-internal-citer"):
            n += 1
    return n


print("# 1. THE CLASS, AND 2. ITS DISARM. One frozen population, three windows.")
print(f"# {'window':>8s} {'G8 armed':>10s} {'G8 disarmed':>13s} {'delta':>7s}")
for w in WINDOWS:
    a = g8_rows(f, w)
    keep = f.copies
    f.copies = set()
    d = g8_rows(f, w)
    f.copies = keep
    print(f"# {('w=' + str(w) + 'm'):>8s} {a:>10d} {d:>13d} {d - a:>+7d}")
print("# -> INVARIANT IN EVERY WINDOW. G8 is not a clause. The corpus filter already answered it.")

print("\n# 3. WHY NO PLANT CAN RESCUE IT:")
with tempfile.TemporaryDirectory() as tmp:
    p = os.path.join(tmp, ".agents/slop/x/a.md")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write("x\n")
    subprocess.run(["git", "init", "-q"], cwd=tmp, capture_output=True)
    subprocess.run(["git", "add", "-A"], cwd=tmp, capture_output=True)
    got = sweep.residue_copies(tmp, [".agents/slop/x/a.md"])
    print(f"#   `residue_copies()` on a synthetic tree -> {got}  (checks/residue.py is not in it)")
    print("#   So a synthetic G8 test measures a MISSING MODULE. **A TEST THAT CANNOT BE RUN IS NOT")
    print("#   A TEST** -- the same lesson clause II taught, arriving in a fourth place.")

# ---- THE PLANT THAT DOES MOVE. One row IN, one row OUT, from one tree and one literal oracle. ---
# THE FIXTURE'S `expect` COLUMN IS A LITERAL. Nothing computes it.
# THE TWO REPORTS MUST NAME DIFFERENT ROWS, OR THE FIXTURE PROVES NOTHING: with one shared body each
# report names both fixtures, excluding one leaves the other, and BOTH rows stay UNKNOWN -- which is
# exactly what the first draft of this plant measured before it was fixed.
IN_REPORT = "see in-row.fixture for the fixture\n"
SELF_REPORT = "see out-row.fixture for the fixture\n"
FIXTURE = [
    # (relpath, content, expect)
    # A row named ONLY by an in-residue report that is not an instrument's own output -> UNKNOWN.
    # THIS FORCES A ROW INTO `UNKNOWN`.
    (".agents/slop/g8/in-row.fixture", "a\n", "UNKNOWN:residue-internal-citer"),
    (".agents/slop/g8/a-report.md", IN_REPORT, "-"),
    # A row named ONLY by a report inside an instrument's OWN OUTPUT DIRECTORY, which
    # `self_output_dirs` DISCOVERS from the module that writes it -- no name for the exclusion
    # appears anywhere in the fixture. The corpus drops that report, the name goes with it, and the
    # row is left with no witness. THIS FORCES A ROW OUT OF `UNKNOWN`, to DELETE.
    (".agents/slop/g8-self/a-report.md", SELF_REPORT, "-"),
    (".agents/slop/g8-self/out-row.fixture", "b\n", "DELETE"),
    # The instrument that writes `.agents/slop/g8-self`. Discovered by `self_output_dirs`, which
    # reads the AST of every `checks/*.py` and never executes one.
    ("checks/fake-instrument.py",
     'import os\nOUT = os.path.join(ROOT, ".agents/slop/g8-self")\n'
     'def go():\n    os.makedirs(OUT, exist_ok=True)\n', "-"),
]


def plant():
    with tempfile.TemporaryDirectory() as tmp:
        for rel, content, _e in FIXTURE:
            p = os.path.join(tmp, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w") as fh:
                fh.write(content)
        g = lambda *a: subprocess.run(["git", *a], cwd=tmp, capture_output=True, text=True)
        g("init", "-q")
        g("add", "-A")
        g("-c", "user.email=p@p", "-c", "user.name=p", "commit", "-qm", "x")
        pf = sweep.Facts(tmp)
        bad, got = [], {}
        for rel, _c, expect in FIXTURE:
            if expect == "-":
                continue
            v = sweep.verdict_for(rel, pf.mentioned, pf)
            got[rel.rsplit("/", 1)[-1]] = v.split(" (")[0]
            if v.split(" (")[0] != expect:
                bad.append(f"    {rel}: want {expect}, got {v.split(' (')[0]}")
        # A BELT THAT SHARES NO ASSUMPTION WITH THE CLASSIFIER: the discovery must find the
        # directory from the module that writes it, with nothing naming it in the fixture.
        disc = set(sweep.self_output_dirs(tmp))
        if ".agents/slop/g8-self" not in disc:
            bad.append(f"    self_output_dirs() -> {sorted(disc)}, expected .agents/slop/g8-self")
        return bad, got


bad, got = plant()
print(f"\n# 4. THE PLANT THAT DOES MOVE: {'FAIL' if bad else 'PASS'}")
for k, v in got.items():
    print(f"#     {k:24s} -> {v}")
for b in bad:
    print(b)
if not bad:
    print("#   ONE ROW FORCED INTO `UNKNOWN` AND ONE ROW FORCED OUT OF IT, FROM ONE TREE.")
    print("#   THE OUT-ROW IS FORCED BY DISCOVERY: `self_output_dirs()` reads the AST of the module")
    print("#   that WRITES the directory, so no name for it appears anywhere in the fixture.")
sys.exit(1 if bad else 0)
