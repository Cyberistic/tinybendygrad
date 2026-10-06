import pathlib, re, subprocess
DEAD = re.compile(r"Traceback \(most recent call last\)|ModuleNotFoundError|FileNotFoundError|"
                  r"error: the following arguments are required|^usage: |ImportError:|"
                  r"error: unrecognized arguments|No module named")
gates = [l.split(None, 2)[:2] for l in
         pathlib.Path(".agents/slop/canrun/canfail.tsv").read_text().splitlines()[1:]]
red = [(g, rc) for g, rc, _ in gates if _ == "RED"] if False else []
lines = pathlib.Path(".agents/slop/canrun/canfail.tsv").read_text().splitlines()[1:]
red = [(p[0], p[1]) for p in (l.split(None, 2) for l in lines) if len(p) == 3 and p[2] == "RED"]
rows = []
for g, rc in red:
    p = subprocess.run([".venv/bin/python", g], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       text=True, timeout=180)
    m = DEAD.search(p.stdout)
    rows.append((g, rc, "CANNOT RUN (dead)" if m else "RAN, verdict is RED", m.group(0) if m else ""))
w = max(len(r[0]) for r in rows)
for g, rc, kind, why in sorted(rows, key=lambda r: (r[2], r[0])):
    print(f"{g:<{w}}  {rc:<5} {kind:<20} {why}")
from collections import Counter
print("\n" + str(Counter(k for _, _, k, _ in rows)))
