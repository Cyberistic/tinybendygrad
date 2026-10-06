#!/usr/bin/env python3
"""RUNTIME measurement: WHERE does each of the twelve root constants POINT, and does the file RUN.

Independent of `gates/gates-pop.py` BY SHAPE, not by regex: the file is imported under the name
`_probe_target`, so `if __name__ == "__main__"` does not fire and no gate body executes, and the
value the FILE ITSELF computed is read out of its namespace. No `parents[n]` arithmetic here and
no `HERE`-is-a-directory guess -- the second belt must not share the first belt's assumption, and
that is a measured lesson here, not a style preference.

Two columns per file, and the pairing is the point:
  REACHED  the directory the constant resolves to, spelled as the file spelled it
  RUNS     whether the module imports cleanly under bare python3

A row that is `OFF-REPO` + `IMPORT=FAIL` is a gate that would crash rather than report; a row that
is `OFF-REPO` + `IMPORT=ok` is the dangerous one, because it reports on the wrong tree silently.

Writes `.agents/slop/offrepo/reached.tsv`. Touches nothing else.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent / "reached.tsv"
REPO_STR = str(ROOT.resolve())

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
    "gates/gates-pop.py",
]

# Ask the MODULE for its value. A literal name list would be the `ORACLE` failure: a file that
# renames its constant would read as having none. Anything that is a Path is reported.
CHILD = '''
import contextlib, importlib.util, io, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("_probe_target", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
buf = io.StringIO()
code = 0
try:
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
        spec.loader.exec_module(mod)
except BaseException as exc:
    # The buffer goes out WITH the failure. MEASURED: the first version dropped it, so a
    # gate that `refuse()`d on a swept INPUT was indistinguishable from one that `refuse()`d
    # on a wrong ROOT -- same exit code, same empty message, opposite verdicts.
    print("FAIL " + type(exc).__name__ + ": " + (buf.getvalue().strip().replace("\\n", " ")
                                                 or str(exc).splitlines()[0][:110]))
    code = 1
if code == 0:
    vals = sorted({str(v) for k, v in vars(mod).items() if isinstance(v, Path)})
    print("OK " + " ;; ".join(vals))
    early = [p for p in sys.path if "src" in p or "tries" in p]
    print("SYS " + " | ".join(early[:4]))
sys.exit(code)
'''


def reach(path):
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as fh:
        fh.write(CHILD)
        script = fh.name
    try:
        r = subprocess.run([sys.executable, script, str(path)], capture_output=True,
                           text=True, timeout=180)
    finally:
        Path(script).unlink()
    out = r.stdout.splitlines()
    ok = next((l[3:] for l in out if l.startswith("OK ")), None)
    fail = next((l[5:] for l in out if l.startswith("FAIL ")), "")
    early = next((l[4:] for l in out if l.startswith("SYS ")), "-")
    return ("IMPORT=ok" if ok is not None else f"IMPORT=FAIL {fail}"), (ok or "-"), early


def on_root(runs, computed):
    """Three states, and the DISCRIMINATOR IS THE MESSAGE'S SHAPE, not the exit code.

    MEASURED, and this is the same shape of error as the two in the brief: a gate that
    `refuse()`s on a SWEPT INPUT has a CORRECT ROOT, a gate that `refuse()`s because
    `REPO does not hold the tree` does not, and both exit 3. An exit code cannot tell them
    apart -- so the discriminator is the clause, read from the file's own words.
    """
    if computed != "-":
        return REPO_STR in computed
    if "is not the repo root" in runs:
        return False
    return REPO_STR in runs   # a refusal that NAMES a path under the repo: the root was right


rows = ["path\truns\tcomputed\tverbatim\tsyspath_early\tonroot"]
for t in TARGETS:
    runs, computed, early = reach(ROOT / t)
    hit = on_root(runs, computed)
    rows.append(f"{t}\t{runs}\t{'yes' if hit else 'NO'}\t{computed}\t{early}"
                f"\t{'on-root' if hit else 'OFF-REPO'}")
    print(f"{t}")
    print(f"    runs   : {runs}")
    print(f"    reached: {computed}")
    print(f"    onroot : {'YES' if hit else 'NO'}")
    print(f"    sys.path: {early}")

OUT.write_text("\n".join(rows) + "\n")
print("\nwrote " + str(OUT.relative_to(ROOT)))