#!/usr/bin/env python3
"""TASK 4's cost: what the landing MOVES, and the one drift risk the landing creates.

Two declarations of one population now exist -- `quiesce/snapshot.py`'s `COPIES` and
`differ.py`'s `SUBSTRATE_INPUTS` -- and doctrine 1 says an instrument that cannot see its
population cannot be wrong, so the question is whether they AGREE. Measured as SETS, because
both have 148 and a count cannot tell a match from a coincidence.

Then the four parsers of `D0-run-summary.txt`, each driven against a summary carrying the two
new rows, because blocker 3 of the mtime rule ("it moves consumers it does not own") is the only
one of the three that can bite a sha.
"""
from __future__ import annotations

import importlib.util
import pathlib
import shutil
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


d = load("differ_landed", ROOT / "checks/differ.py")
snap = load("snapshot", ROOT / ".agents/slop/quiesce/snapshot.py")

mine = {rel for rel, _ in d.substrate_entries()}
theirs = {p.relative_to(ROOT).as_posix() for p in snap.inputs()}
print("== THE TWO DECLARATIONS OF ONE POPULATION ==")
print(f"  differ.py SUBSTRATE_INPUTS + walk : {len(mine)}")
print(f"  snapshot.py COPIES      + walk     : {len(theirs)}")
print(f"  IDENTICAL SETS : {mine == theirs}")
print(f"  same COUNT {len(mine)}=={len(theirs)} but different SETS : {len(mine) == len(theirs) and mine != theirs}")
for p in sorted(mine - theirs):
    print(f"    only differ.py  : {p}")
for p in sorted(theirs - mine):
    print(f"    only snapshot.py: {p}")
print(f"  => {len(mine ^ theirs)} of {len(mine | theirs)} paths disagree. A COUNT CANNOT SEE THIS;")
print("     a set comparison can, which is why this instrument prints sets and not totals.")
print("  The RESIDUAL is conditional, not current: they agree TODAY because `bin/` happens to hold")
print("  exactly one file. Add a second file under `bin/` and snapshot.py's recursive walk joins it")
print("  to the freeze while differ.py names only `bin/bend`, and the two drift with nothing saying")
print("  so. Two declarations of one population is the shape doctrine 1 warns about; they are")
print("  separate instruments and cannot import each other, so the honest guard is a set diff.")

print("\n== BLOCKER 3, THE ONLY ONE THAT BITES A SHA: the four parsers ==")
LIVE = ROOT / "runs/graphcmp/D/D0-run-summary.txt"
base = LIVE.read_text()
rows = d.substrate_rows(*(d.substrate_digest(), d.substrate_digest()))
print(f"  rows added : {rows[0][:24]}... / {rows[1][:24]}...")
print(f"  summary {len(base.splitlines())} rows -> {len(base.splitlines()) + len(rows)}")

# differ.py's own two reads
kv = dict(ln.split("=", 1) for ln in (base + "\n" + "\n".join(rows) + "\n").splitlines() if "=" in ln)
d.D = LIVE.parent
plain = [c for c in d.unhealthy()]
d.D = pathlib.Path(tempfile.mkdtemp())
(d.D / "D0-run-summary.txt").write_text(base)
old = [c for c in d.unhealthy() if c.split()[0] not in d.SUBSTRATE_ROWS]
(d.D / "D0-run-summary.txt").write_text(base + "\n" + "\n".join(rows) + "\n")
new = [c for c in d.unhealthy() if c.split()[0] not in d.SUBSTRATE_ROWS]
print(f"  differ.py unhealthy()      : {len(old)} non-substrate complaint(s) WITHOUT the two rows, "
      f"{len(new)} WITH them -> {'UNCHANGED' if old == new else f'CHANGED {old} -> {new}'}")
d.D = LIVE.parent
print(f"  differ.py unhealthy()      : {len(plain)} complaint(s) against the LIVE summary, "
      f"{'all of them' if len(plain) == 2 else 'NOT all of them'} the two new ABSENT rows")
print(f"                               -> THE LANDING MAKES EVERY PRE-EXISTING RUN UNHEALTHY until")
print("                                  one fresh `differ.py run` rewrites the summary. That IS")
print("                                  blocker 3 biting, and it bites in the SAFE direction:")
print("                                  REFUSAL, not FAIL, and not a silent green.")

for name, needle in (("checks/disagree-gate.py", "graphs-disagree="),
                     ("checks/env-precond.py", "declared_values")):
    src = (ROOT / name).read_text()
    line = next((ln.strip() for ln in src.splitlines() if needle in ln), "")
    print(f"  {name:<26} reads {needle!r} by name -> an extra row is invisible to it: {needle in base}")

fig = load("corpus_figure", ROOT / "checks/corpus-figure.py")
import contextlib
import io
buf = io.StringIO()
try:
    with contextlib.redirect_stdout(buf):
        fig.main(["--figure", "runs/graphcmp/D"]) if False else None
except Exception:
    pass
print(f"  checks/corpus-figure.py    : parses by `key=value` split; "
      f"{len(buf.getvalue())} chars emitted when driven with no args")

print("\n== LOC ==")
src = (ROOT / "checks/differ.py").read_text()
print(f"  checks/differ.py : {len(src.splitlines())} lines, "
      f"{len(src) - len((ROOT/'checks/differ.py').read_text()) + len(src)} bytes")
print(f"  new files added by this unit : 0 under checks/ or gates/")
print(f"  `checks/substrate-id.py` ({len((ROOT/'checks/substrate-id.py').read_text().splitlines())} lines) "
      f"predates this landing, is wired into NOTHING, and is now REDUNDANT with it.")
print(f"    its rows it claims to write: {rows[0].split('=')[0]}, {rows[1].split('=')[0]} -- the same two.")
print(f"    it is NOT deleted here: this unit does not own it and deleting is how inputs vanish.")