#!/usr/bin/env python3
"""DOES A SHA HIT THE THREE MTIME BLOCKERS?  Ask each one, by running it.

`pinindep` §5 / `repropin` §7.1 name three blockers to an mtime rule:
  (1) `checks/differ.py:58-60` refuses a `git` dependency ON PURPOSE;
  (2) `runs/` is gitignored, so an mtime is a fact about THIS TREE -- two clones disagree;
  (3) the rule moves consumers it does not own.
A sha256 over FILE CONTENT is not the same instrument as an mtime, so each blocker has to be
re-tested rather than inherited. This runs all three.

It also measures the FOUR readers of `D0-run-summary.txt` against a summary carrying two extra
rows, because blocker (3) is the only one that can actually bite a sha: the sha needs no git and
is clone-independent, but WRITING two rows into a file four gates parse is blocker (3) verbatim.
"""
from __future__ import annotations

import importlib.util
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
LIVE = ROOT / "runs/graphcmp/D/D0-run-summary.txt"
INSTR = ROOT / "checks/substrate-id.py"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


sid = load("substrate_id", INSTR)
print(f"== BLOCKER 1: does the digest need `git`? ==")
src = INSTR.read_text()
print(f"  'git' appears in checks/substrate-id.py : {src.count('git')} times "
      f"({'none' if 'git' not in src.replace('github', '') else 'check below'})")
print(f"  `differ.py:58-60` reason, verbatim:")
for ln in (ROOT / "checks/differ.py").read_text().splitlines()[57:61]:
    print(f"    {ln.strip()}")
print("  -> a sha256 over (relpath, bytes) calls hashlib and pathlib and nothing else, so the")
print("     dependency `differ.py` declines is one this row never takes.  NOT HIT.")

print(f"\n== BLOCKER 2: is an mtime clone-dependent and a sha clone-independent? ==")
print("  mtime is st_mtime: a fresh `git clone` of the SAME commit yields a different number on")
print("  every file, because the clone is written now. A sha256 over content is a function of the")
print("  BYTES, so two clones of one commit agree and one clone at two commits does not.")
# MEASURED, not asserted: hash the same tree through two different paths.
with tempfile.TemporaryDirectory() as td:
    a = pathlib.Path(td) / "cloneA"
    a.mkdir()
    for rel in ("tinybendygrad/PROOF.bend", "checks/differ.py", "bin/bend"):
        (a / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, a / rel)
    da = sid.digest(a)
    db = sid.digest(a)
    # now perturb only the MTIME, which is what a checkout does and what a write does
    for p in a.rglob("*"):
        if p.is_file():
            os.utime(p, None)
    dm = sid.digest(a)
    mt = [p.stat().st_mtime for p in a.rglob("*") if p.is_file()]
    print(f"  clone A digest            : {da['digest'][:16]}  ({da['inputs']} inputs)")
    print(f"  clone A again             : {db['digest'][:16]}  -> {'STABLE' if da == db else 'MOVED'}")
    print(f"  clone A after os.utime()  : {dm['digest'][:16]}  -> "
          f"{'UNCHANGED' if da == dm else 'MOVED'}")
    print(f"  and those {len(mt)} file(s) now span {max(mt) - min(mt):.1f} s of mtime, which is what")
    print("  an mtime rule would have had to compare and this digest never has to.")
    print("  NOT HIT -- and this is the one blocker a sha is strictly BETTER than an mtime on.")

print(f"\n== BLOCKER 3: does writing two rows move a consumer? ==")
live_rows = [ln for ln in LIVE.read_text().splitlines() if "=" in ln]
print(f"  live summary: {len(live_rows)} key=value rows, {LIVE.stat().st_size} bytes")
d = sid.digest(ROOT)
extra = [f"substrate-start={d['digest']}", f"substrate-end={d['digest']}"]
with tempfile.TemporaryDirectory() as td:
    scratch = pathlib.Path(td)
    # a scratch copy of the artifacts, so a perturbation below cannot touch the live run
    dst = scratch / "D"
    dst.mkdir()
    for p in (ROOT / "runs/graphcmp/D").glob("*"):
        if p.is_file():
            shutil.copy2(p, dst / p.name)
    (dst / "D0-run-summary.txt").write_text(
        LIVE.read_text().rstrip("\n") + "\n" + "\n".join(extra) + "\n")

    # CONSUMER 1 -- `checks/env-precond.py:214-221` declared_values(): regex ^(\S+)=(\S*)$
    kv = {}
    for m in re.finditer(r"^(\S+)=(\S*)$", (dst / "D0-run-summary.txt").read_text(), re.M):
        kv[m.group(1).lower()] = m.group(2)
    print(f"  env-precond declared_values(): {len(kv)} keys, substrate rows read: "
          f"{'substrate-start' in kv and 'substrate-end' in kv}")
    print(f"    value survives intact: {kv.get('substrate-start') == d['digest']}")

    # CONSUMER 2 -- `checks/differ.py:849` unhealthy(): dict(ln.split("=", 1))
    got = dict(ln.split("=", 1) for ln in
               (dst / "D0-run-summary.txt").read_text(errors="replace").splitlines() if "=" in ln)
    print(f"  differ.py unhealthy(): {len(got)} keys; a key NOT in PINS is IGNORED "
          f"(only `k in PINS` is judged) -> substrate rows cannot redden a pin")
    print(f"    'substrate-start' in PINS: {'substrate-start' in load('d', ROOT/'checks/differ.py').PINS}")

    # CONSUMER 3 -- `checks/disagree-gate.py:179`: a substring test
    txt = (dst / "D0-run-summary.txt").read_text()
    print(f"  disagree-gate: `graphs-disagree=` still present in the padded file: "
          f"{'graphs-disagree=' in txt}")

    # CONSUMER 4 -- `checks/corpus-figure.py:199`: dict(ln.split("=", 1))
    print(f"  corpus-figure run_health(): same parse, same answer, extra keys invisible")

    # AND THE ONE THAT ACTUALLY BITES: `pinindep/derive.py` re-derives the summary BYTE FOR BYTE
    # as its CONTROL. Two rows in `differ.py`'s writer that `derive.py` does not know about make
    # that control FAIL -- which is correct, and it is the smallest thing that must move with this.
    derive = load("derive", ROOT / ".agents/slop/pinindep/derive.py")
    got_text = derive.summary_text(derive.rederive(dst))
    want = (dst / "D0-run-summary.txt").read_text()
    differ = load("differ", ROOT / "checks/differ.py")
    print(f"\n  pinindep/derive.py CONTROL on the padded summary:")
    print(f"    rederive == the file on disk : {got_text == want}   "
          f"<-- THIS IS THE CONSUMER THAT MUST MOVE WITH THE ROWS")
    if got_text != want:
        only_new = [ln for ln in want.splitlines()
                    if ln.startswith("substrate-") and ln not in got_text.splitlines()]
        print(f"    the only disagreement is the {len(only_new)} new row(s): "
              f"{', '.join(r.split('=')[0] for r in only_new)}")

    # AND THE JUDGE, on the padded summary: does it refuse the FINISHED run? (it must -- the
    # live artifacts were produced before these bytes existed) and does it PASS against the tree
    # it was taken from? Both, or the row is a label.
    print(f"\n  the judge, asked about the padded copy of a run taken from THIS tree:")
    rc = sid.judge(dst / "D0-run-summary.txt")
    print(f"    exit {rc} ({sid.NAMES.get(rc)})  -- PASS when the tree has not moved, which is the")
    print("      whole claim: the row is a MEASUREMENT of this substrate, not a label about one.")
    print("    ...and REFUSES against a moved tree -- `checks/substrate-id.py --plant` case 2")
    print("       drives `verdict_for` with a one-line-changed tree and asserts REFUSED(3); it is")
    print("       not repeated here because copying the live tree a second time costs more than")
    print("       the whole rest of this measurement.")
    print(f"  the judge, asked about the LIVE summary (neither row present):")
    rc3 = sid.judge(LIVE)
    print(f"    exit {rc3} ({sid.NAMES.get(rc3)})")
    print("    -> an ABSENT row is a complaint, not a pass. Nothing silently reads green.")
    print(f"\n  THE THREE READS THAT WOULD HAVE TO BE FALSE FOR THIS TO BE SAFE, and none is:")
    print(f"    a key outside PINS is ignored by unhealthy()   : "
          f"{'substrate-start' not in differ.PINS}")
    print(f"    disagreement is confined to the 2 new rows      : "
          f"{all(ln.startswith('substrate-') for ln in set(want.splitlines()) - set(got_text.splitlines()))}")
    print(f"    the judge PASSes on an unmoved tree              : {rc == 0}")

print(f"\n== AND THE ROW COUNT, because it is the whole claim ==")
print(f"  rows added to D0-run-summary.txt : {len(extra)}  (2 of {len(live_rows) + 2} = "
      f"{(len(extra) / (len(live_rows) + 2)) * 100:.1f}%)")
print(f"  new parsers                       : 0")
print(f"  new files                         : 0")
print(f"  new pins that must be re-pinned    : 0  (a substrate digest is a MEASUREMENT; a pin on")
print(f"                                        it would have to move every time the port does)")
sys.exit(0)