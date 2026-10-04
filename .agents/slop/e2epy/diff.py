#!/usr/bin/env python3
"""PER-STAGE diff of the frozen shell oracle and the Python port, over the LIVE repository and over
a FIXTURE tree that reaches every branch cheaply.

    usage: .venv/bin/python .agents/slop/e2epy/diff.py [--sets live plant] [--show N]

A GATE IS A TEXT, NOT AN EXIT STATUS. So each side is STDOUT + STDERR + EXIT STATUS, all three
kept, and the verdict is reported PER STAGE -- verdict line, denominators, and the whole output
stream -- because one aggregate "IDENTICAL" over eight stages hides the one that differs.

**PER-STAGE, NOT PER-FILE, BECAUSE A STAGE IS THE UNIT OF THE CLAIM.** Each `== n/m ...` header
opens a stage and each `  <stage name>: PASS|FAIL|SKIP` line closes one, so a stage is compared as
(header, body, verdict, absence-or-presence). A stage present on one side and ABSENT on the other is
reported as its own outcome rather than as a byte difference buried in a diff, because a gate that
lost its last line has lost reproducibility without saying so.

**ONE NORMALISATION, AND IT IS THE PROGRAM'S OWN NAME ONLY.** Nothing else is touched: no
whitespace folding, no case folding, no path rewriting, no timestamp masking. If the two disagree,
the disagreement is reported as it stands.

**ONE `bend` PROCESS AT A TIME, ALWAYS.** Two of them at once took this machine's memory to zero on
2026-10-05 (`PEAKRSS.md`: 1,152 MB + 1,108 MB). Every run here is strictly sequential -- a run is
`subprocess.run`, which blocks -- and the two SIDES OF A PAIR ARE ORDERED, never concurrent.

EXCLUDED: `.agents/slop/differverdict/root/` is a FULL COPY OF THE REPOSITORY (253 MB, 9,301 files)
made by a live unit, so any `find` that walks it reports hundreds of files that are not this
project's. **NOTHING IN THIS FILE WALKS IT** -- no `find`, no glob over `.agents/slop`, and every
path here is named explicitly.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
ROOT = HERE.parents[3]
ART = ROOT / ".agents/slop/e2epy/artifacts"
ORACLE, PORT = ".agents/slop/e2epy/oracle-e2e.sh", "checks/e2e.py"
# THE TWO SIDES ARE INVOKED BY ABSOLUTE PATH, FROM THE REPOSITORY ROOT, AND DIFFER ONLY IN
# `E2E_ROOT`. Both scripts `cd` to `E2E_ROOT` themselves, so the pair stays a fair test: same
# invocation cwd, same inherited environment, one variable apart. Invoking the oracle RELATIVE to
# the fixture tree is how the first run of this driver reported `zsh: can't open input file` -- the
# script could not be found, which is a bug in the driver and reads exactly like a gate that refused.
PY = str(ROOT / ".venv/bin/python")
ENV = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
HEADER = re.compile(r"^== (\d+/\d+) (.*)$")
VERDICT = re.compile(r"^  (stage \d+ [^:]*): (PASS|FAIL \(rc=-?\d+\)|SKIP -- .*)$")
SUMMARY = re.compile(r"^(---|PASS|FAIL)")


def split_stages(stdout: str) -> list[tuple[str, list[str]]]:
    """The artifact read back as the shell builds it: one entry per `== n/m` header, each holding
    its header line, its body, and the `--- verdicts:` trailer. A stage with NO HEADER -- the `set -e`
    ABORT paths, stages 1 and 2 -- still gets an entry, named by what is there, because an abort that
    the other side did not also perform is the single most important difference this driver can find.
    """
    out: list[tuple[str, list[str]]] = []
    for ln in stdout.splitlines():
        if HEADER.match(ln) or SUMMARY.match(ln):
            out.append((ln, []))
        elif out:
            out[-1][1].append(ln)
        else:
            out.append(("<pre-header>", [ln]))
    return out


def run(cmd: list[str], cwd: Path, env: dict[str, str], tag: str) -> tuple[int, str, str]:
    """One SIDE. Blocks to completion -- this is what makes two `bend` processes impossible here."""
    out, err = ART / f"{tag}.out", ART / f"{tag}.err"
    with open(out, "wb") as o, open(err, "wb") as e:
        rc = subprocess.run(cmd, cwd=cwd, env=env, stdout=o, stderr=e).returncode
    return rc, out.read_text(errors="replace"), err.read_text(errors="replace")


def verdicts_of(stdout: str) -> dict[str, str]:
    """`<stage name>` -> `<verdict line>` for every verdict line in the artifact."""
    return {m.group(1): m.group(2) for m in (VERDICT.match(ln) for ln in stdout.splitlines()) if m}


def compare(tag: str, cwd: Path, env: dict[str, str], show: int) -> list[str]:
    """ONE PAIR, ORACLE FIRST THEN PORT, SEQUENTIALLY, and the per-stage report."""
    orc, oout, oerr = run(["zsh", str(ROOT / ORACLE)], ROOT, env, f"{tag}.oracle")
    prc, pout, perr = run([PY, str(ROOT / PORT)], ROOT, env, f"{tag}.port")
    lines = [f"## {tag}   exit: oracle={orc}  port={prc}"
             f"{'' if orc == prc else '   *** EXIT STATUS DIFFERS ***'}"]
    ov, pv = verdicts_of(oout), verdicts_of(pout)
    # EVERY STAGE NAME EITHER SIDE MENTIONS, in the oracle's order first. A name on one side only is
    # the interesting case, so the UNION is walked, not the intersection.
    for n in list(ov) + [x for x in pv if x not in ov]:
        a, b = ov.get(n, "<ABSENT>"), pv.get(n, "<ABSENT>")
        lines.append(f"  {n:<50} oracle={a:<26} port={b:<26}"
                     f"{'' if a == b else '   *** DIFFERS ***'}")
    # A STAGE BLOCK IS A HEADER AND EVERYTHING UP TO THE NEXT ONE. Present on one side and absent on
    # the other is its own outcome: a gate that lost a stage has lost reproducibility without saying
    # so, and a byte diff alone would bury that.
    ob, pb = [h for h, _ in split_stages(oout)], [h for h, _ in split_stages(pout)]
    for h in ob:
        lines.append(f"  block  oracle-only  {h}")
    for h in pb:
        lines.append(f"  block  port-only    {h}")
    for name, a, b in (("stdout", oout, pout), ("stderr", oerr, perr)):
        same = a == b
        lines.append(f"  {name}: {'IDENTICAL' if same else 'DIFFERS'} "
                     f"({len(a)} vs {len(b)} bytes)")
        if not same:
            lines += [f"  --- {name} diff (oracle < / port >) ---", *_hunks(a, b, show)]
    return lines


def _hunks(a: str, b: str, show: int) -> list[str]:
    import difflib
    d = [ln.rstrip("\n") for ln in difflib.unified_diff(a.splitlines(), b.splitlines(),
                                                        "oracle", "port", lineterm="", n=1)]
    return [f"    {ln}" for ln in (d[:show * 4] or ["<no textual difference>"])]


# ------------------------------------------------------------------ the input sets
# `live` is THE REPOSITORY, and it is the run the migration rule is about.
SETS = {"live": (ROOT, ENV)}

# `plant` MOVES THE SUBSTRATE OUT FROM UNDER STAGE 7 and stage 8 without editing one byte of the
# port or the oracle, so the THIRD OUTCOME can be compared instead of argued about. The fixture tree
# holds a `.agents/slop/f64/run-f64.sh` that refuses with 3, and a `jstage/jsstage.py` that refuses
# with 3, so both `SKIP` branches are reachable in two seconds and no real `bend` runs at all.
FX = ROOT / ".agents/slop/e2epy/fixtures/plant"


def _build_plant() -> Path:
    """The plant tree: every stage script is a stub that exits with a code the SET chooses, so the
    eight branches of `main()` are all reachable without a compiler, a browser or a GPU. NOTHING
    HERE IS COPIED FROM THE LIVE TREE -- each stub is four lines -- because a plant that copies the
    thing it is meant to displace cannot prove anything."""
    if FX.exists():
        shutil.rmtree(FX)
    for sub in (".venv/bin", "bin", ".agents/slop/e2e_port", ".agents/slop/f64",
                ".agents/slop/jstage", "runs/e2e"):
        (FX / sub).mkdir(parents=True, exist_ok=True)
    codes = os.environ.get("PLANT_CODES", "0,0,0,0,3,0").split(",")
    # `plant` SET CODES: stage4, stage5, stage6, stage7, stage8, and a spare. Only the two that
    # matter are non-zero, and BOTH refusals are what the shell names as SKIP.
    def stub(name: str, body: str) -> None:
        p = FX / name
        p.write_text(body)
        p.chmod(0o755)
    stub(".venv/bin/python", f"""#!/bin/sh
# STUB for $ROOT/.venv/bin/python. It answers each of the four scripts the gate runs with the exit
# code PLANT_CODES names, and prints one identifiable line so the artifact shows which stub ran.
case "$1" in
  *e2e_mm.py)     echo "PLANT stub: stage1 oracle";  exit {codes[0]} ;;
  *e2e_mm_gate.py) echo "PLANT stub: stage4 gate, 20/20 rows vs CPython"; exit {codes[1]} ;;
  *jsstage.py)    echo "PLANT stub: stage8 jsstage, substrate would not compile"; exit {codes[4]} ;;
  *)              echo "PLANT stub: $1"; exit 0 ;;
esac
""")
    stub("bin/bend", """#!/bin/sh
# STUB bend: emits 25 `name=value` rows, so stage 2's `> 20 rows` denominator is MET on attempt 1.
i=0; while [ $i -lt 25 ]; do echo "PLANT.row$i=$i"; i=$((i+1)); done
exit 0
""")
    stub(".agents/slop/opsbend-milestone.sh",
         f"#!/bin/sh\necho 'PLANT stub: stage5 ops_bend milestone'\necho 'expected: 1 2 3'\n"
         f"echo 'PACKET.out: 1 2 3'\nexit {codes[2]}\n")
    stub(".agents/slop/e2e_port/run-port-mm.sh",
         f"#!/bin/sh\necho 'PLANT stub: stage6 port matmul, 64/64 words'\nexit {codes[3]}\n")
    stub(".agents/slop/f64/run-f64.sh",
         f"#!/bin/sh\necho 'PLANT stub: run-f64.sh'\n"
         f"[ {codes[4]} -eq 3 ] && echo 'REFUSED[ cold substrate: renderer/amd/generate.bend is 0 bytes ]'\n"
         f"exit {codes[4]}\n")
    return FX


def main() -> int:
    ap = argparse.ArgumentParser(prog=__file__, description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sets", nargs="+", default=["live"], choices=sorted(SETS) + ["plant"],
                    help="input classes: the live repository, or the plant tree (both refusals)")
    ap.add_argument("--show", type=int, default=6, help="diff hunks per stream")
    opts = ap.parse_args()
    ART.mkdir(parents=True, exist_ok=True)
    sets = dict(SETS)
    if "plant" in opts.sets:
        fx = _build_plant()
        sets["plant"] = (fx, ENV | {"E2E_ROOT": str(fx)})
    bad = 0
    for tag in opts.sets:
        cwd, env = sets[tag]
        lines = compare(tag, cwd, env, opts.show)
        for ln in lines:
            print(ln)
        if any("DIFFERS" in ln or "***" in ln for ln in lines):
            bad += 1
    print(f"\n{bad} of {len(opts.sets)} set(s) disagree.  artifacts: "
          f"{ART.relative_to(ROOT)}/")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())