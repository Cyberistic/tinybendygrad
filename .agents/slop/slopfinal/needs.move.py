#!/usr/bin/env python3
"""EVERY `needs=` CLASS, WITH A NUMBER THAT MOVES WHEN THE CONDITION IT DESCRIBES IS CHANGED.

**BEFORE ADDING A `needs=`, ESTABLISH THAT ITS NUMBER MOVES.** A clause that is invariant under the
change it claims to measure is not a clause -- `gates/retention-check.py`'s clause II is the worked
example: delete the `finally` from `gates/gatekit.py`'s `run()` and it still reports the same pair.

So each row below is planted, then its CONDITION is changed, and the number is read twice. `expect`
IS A LITERAL in the fixture; nothing computes it.

THE FIXTURE IS ONE TREE. Each `needs=` row is reachable, and each arm below changes exactly the
condition its own `needs=` names -- a second corpus mention, an index entry, a committed report --
and changes NOTHING else, so a moved number is attributable.
"""
import importlib.util, os, subprocess, sys, tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


sweep = load("sweep", os.path.join(ROOT, "checks/sweep.py"))

# (relpath, content, tracked, expect)
FIXTURE = [
    # An EXTERNAL corpus file. Belt A's regex needs a leading alphanumeric and belt B's `str.translate`
    # table does not, so the text `-gate.sh` yields `gate.sh` for one belt and `-gate.sh` for the
    # other. **THIS IS THE MINIMAL REPRODUCER, MEASURED, NOT GUESSED**: the shipped comment blames a
    # truncating pattern, and the real mechanism is a LEADING HYPHEN that one belt swallows and the
    # other splits on. A row named `gate.sh` is therefore in exactly one belt.
    ("checks/plant-authority.md", "-gate.sh\n", True, "-"),
    (".agents/slop/n1/gate.sh", "a\n", True, "UNKNOWN:belts-disagree"),
    # A TOOL, tracked, whose own directory holds no committed report.
    (".agents/slop/n2/tool-witness.py", "a\n", True,
     "UNKNOWN:commit-the-report-that-explains-it"),
    # An OUTPUT, untracked, that nothing renders or names.
    (".agents/slop/n3/untracked.fixture", "a\n", False, "UNKNOWN:commit-or-drop"),
    # A row named only from inside the residue, by a report that is not an instrument's own output.
    (".agents/slop/n4/a-report.md", "see in-row.fixture\n", True, "-"),
    (".agents/slop/n4/in-row.fixture", "a\n", True, "UNKNOWN:residue-internal-citer"),
    # A row named only from inside an instrument's OWN OUTPUT DIRECTORY, which is DISCOVERED from the
    # module that writes it. The corpus drops that report, so the row has no witness at all.
    (".agents/slop/n5-self/a-report.md", "see out-row.fixture\n", True, "-"),
    (".agents/slop/n5/out-row.fixture", "a\n", True, "DELETE"),
    ("checks/fake-instrument.py",
     'import os\nOUT = os.path.join(ROOT, ".agents/slop/n5-self")\n'
     'def go():\n    os.makedirs(OUT, exist_ok=True)\n', True, "-"),
]

# THE CONDITION CHANGED, ONE PER CLASS. Each is the smallest edit that turns its own `needs=` off.
ARMS = {
    # belts-disagree: name the row the second belt's way too, so both belts see it.
    "belts-disagree": ("write `gate.sh` into the external corpus as well",
                       {"checks/plant-authority.md": "-gate.sh gate.sh\n"}),
    # commit-or-drop: put the row in the index. Git can now restore it, which is the whole condition.
    "commit-or-drop": ("`git add` the untracked row", {}),
    # commit-the-report: commit a report in the row's OWN directory. Mechanical and decidable.
    "commit-the-report-that-explains-it":
        ("commit a report beside the tool", {".agents/slop/n2/why.md": "what this tool is for\n"}),
    # residue-internal-citer: an EXTERNAL corpus file names the row, so the ambiguity is resolved.
    "residue-internal-citer": ("name the row from outside the residue",
                                {"checks/plant-authority.md": "-gate.sh in-row.fixture\n"}),
}


def run(arm=None):
    """Classify the fixture. `arm` names one entry of `ARMS`, whose edits are applied first."""
    edits = ARMS[arm.partition(":")[2]][1] if arm else {}
    with tempfile.TemporaryDirectory() as tmp:
        for rel, content, tracked, _e in FIXTURE:
            p = os.path.join(tmp, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w") as fh:
                fh.write(content)
        for rel, content in edits.items():
            p = os.path.join(tmp, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w") as fh:
                fh.write(content)
        g = lambda *a: subprocess.run(["git", *a], cwd=tmp, capture_output=True, text=True)
        g("init", "-q")
        g("add", "-A")
        for rel, _c, tracked, _e in FIXTURE:
            if not tracked:
                g("rm", "-q", "--cached", rel)
        g("-c", "user.email=p@p", "-c", "user.name=p", "commit", "-qm", "x")
        if arm.partition(":")[2] == "commit-or-drop":     # THE CONDITION, CHANGED: now it IS in the index.
            g("add", "-A")
        pf = sweep.Facts(tmp)
        out = {}
        for rel, _c, _t, expect in FIXTURE:
            if expect == "-":
                continue
            got = sweep.verdict_for(rel, pf.mentioned, pf).split(" (")[0]
            out[expect] = (got, expect)
        return out, pf


base, _ = run()
CLASSES = [e for _r, _c, _t, e in FIXTURE if e.startswith("UNKNOWN")]
print("# EVERY `needs=` CLASS REACHABLE IN ONE TREE, EACH WITH ITS CONDITION CHANGED IN TURN.")
print(f"# {'class':40s} {'planted':>8s} {'moved':>6s}  what changed")
rc = 0
for expect in CLASSES:
    cls = expect.partition(":")[2]
    changed, _pf = run(expect)
    was, now = base[expect][0], changed[expect][0]
    if was != expect or now == was:
        rc |= 1
    print(f"# {cls:40s} {1:>8d} {'YES' if was != now else 'NO':>6s}  {ARMS[cls][0]}")
print()
for expect in CLASSES:
    cls = expect.partition(":")[2]
    changed, _ = run(expect)
    print(f"#   {cls:40s} {base[expect][0]:44s} -> {changed[expect][0]}")
print("\n# EACH ROW IS: the class holds 1 row in the planted tree, and the row LEAVES the class when the")
print("# thing the class names stops being true -- the second belt agrees, git can restore it, a report")
print("# beside it is committed, an outside witness names it. A class whose count survives its own")
print("# condition being false is a label, which is the test clause II failed.")
sys.exit(rc)
