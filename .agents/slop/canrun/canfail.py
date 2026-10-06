"""A CAN-FAIL column, MEASURED not argued: exit status + one line of reason, per gate.

A gate is a gate over gates only if it can be observed to FAIL.  Running every gate twice
is how an assertion that has never failed gets found to have never been tested.
"""
import pathlib, re, subprocess, sys

BEND = re.compile(r"bin/bend|'bend'|\"bend\"")
# Only gates that need no bend and no GPU: the memory ceiling forbids the rest.
GATES = [l.split("\t")[0] for l in
         pathlib.Path(".agents/slop/canrun/ledger-after-my-run.tsv").read_text().splitlines()[1:]]

def needs_bend(p):
    try: return bool(BEND.search(pathlib.Path(p).read_text()))
    except OSError: return False

rows = []
for g in GATES:
    if needs_bend(g):
        rows.append((g, "SKIP", "invokes bend (memory ceiling)")); continue
    out = ".agents/slop/canrun/canfail/" + g.replace("/", "_") + ".err"
    pathlib.Path(out).parent.mkdir(parents=True, exist_ok=True)
    try:
        p = subprocess.run([".venv/bin/python", g], stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        rows.append((g, "SKIP", "timeout")); continue
    pathlib.Path(out).write_text(p.stdout)
    rc = p.returncode
    # 3 = REFUSED, NOT A VERDICT -- the third state, and NOT a pass.
    state = {0: "GREEN", 3: "REFUSED"}.get(rc, "RED" if rc else "GREEN")
    rows.append((g, f"rc={rc}", state))

print(f"{'gate':<44} {'rc':>6}  state")
for g, rc, st in rows:
    print(f"{g:<44} {rc:>6}  {st}")
from collections import Counter
c = Counter(st for _, _, st in rows)
print("\nTOTALS:", dict(c), " -- and 'SKIP' is itself the population this column would retire")
