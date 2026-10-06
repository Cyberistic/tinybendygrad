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


def run(cmd: list[str], env: dict[str, str], tag: str) -> tuple[int, str, str]:
    """One SIDE. `subprocess.run` BLOCKS to completion, and it is the only way a process is started
    here, which is what makes two concurrent `bend` processes impossible in this driver."""
    out, err = ART / f"{tag}.out", ART / f"{tag}.err"
    with open(out, "wb") as o, open(err, "wb") as e:
        rc = subprocess.run(cmd, cwd=ROOT, env=env, stdout=o, stderr=e).returncode
    return rc, out.read_text(errors="replace"), err.read_text(errors="replace")


def verdicts_of(stdout: str) -> dict[str, str]:
    """`<stage name>` -> `<verdict line>` for every verdict line in the artifact."""
    return {m.group(1): m.group(2) for m in (VERDICT.match(ln) for ln in stdout.splitlines()) if m}


# THE ONE NORMALISATION, AND IT IS THE SHELL'S OWN LINE PREFIX. `sh` reports a command it cannot find
# with its location -- `<script>: line 185: zsh: command not found` -- and `checks/e2e.py` has no line
# 185 to name, because it is not the shell. So the prefix is stripped from BOTH sides and the
# remaining question ("which program is missing?") is compared byte for byte. Nothing else is
# touched: no whitespace folding, no path rewriting, no timestamp masking, no case folding. If the
# two still disagree, the disagreement is reported as it stands.
SHELL_LOC = re.compile(rb"^.*: line \d+: ", re.M)


def canon(raw_: bytes) -> bytes:
    return SHELL_LOC.sub(b"", raw_)


def compare(tag: str, env: dict[str, str], show: int) -> list[str]:
    """ONE PAIR, ORACLE FIRST THEN PORT, SEQUENTIALLY, and the per-stage report.

    `sh` IS INVOKED BY ABSOLUTE PATH, BECAUSE THE ORACLE'S SHEBANG IS `#!/bin/sh` AND MEASURED HERE:
    `env -i PATH=/tmp/emptydir /bin/sh -c 'echo $PATH'` prints `/tmp/emptydir`, and the same
    command under `/bin/zsh` prints `/Users/cyberistic/.nub/node-shim:/Users/cyberistic/.cargo/bin:
    /tmp/emptydir` -- zsh REWRITES `PATH` before the first line of any script runs. An earlier cut of
    this driver invoked the oracle with `zsh`, and the two `hide` plants duly disagreed: the oracle
    found the node its own PATH had been stripped of, and `stage-no-node` reported `FAIL rc=1` where
    the port, run under python and therefore under no rewriting shell, correctly reported `SKIP`.
    **THAT WAS THE DRIVER DISAGREEING WITH ITSELF, NOT THE PORT.** Absolute `sh` also leaves
    `plant-no-zsh` able to withhold zsh from the gate while this driver still has an interpreter.
    """
    orc, oout, oerr = run([SH, str(ROOT / ORACLE)], env, f"{tag}.oracle")
    prc, pout, perr = run([PY, str(ROOT / PORT)], env, f"{tag}.port")
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
    # A STAGE BLOCK IS A HEADER AND EVERYTHING UP TO THE NEXT ONE. Present on one side and absent on
    # the other is its own outcome: a gate that lost a stage has lost reproducibility without saying
    # so, and a byte diff alone would bury that. Matched blocks are compared IN ORDER, because the
    # order is the order the claims come in.
    # CANON IS APPLIED HERE TOO, not only to the byte comparison below. The stage blocks are split
    # from the RAW text, so without this a single shell line-prefix inside one block marks that block
    # DIFFERS while the stream as a whole reports IDENTICAL -- two verdicts for one difference, and
    # the reader cannot tell which one to believe.
    ob, pb = split_stages(canon(oout.encode()).decode(errors="replace")), \
        split_stages(canon(pout.encode()).decode(errors="replace"))
    if len(ob) != len(pb):
        lines.append(f"  *** STAGE BLOCK COUNT DIFFERS: oracle={len(ob)} port={len(pb)}")
    for i, ((ha, ba), (hb, bb)) in enumerate(zip(ob, pb)):
        state = "IDENTICAL" if (ha, ba) == (hb, bb) else "DIFFERS"
        lines.append(f"  block {i} {state:<10} {ha}"
                     + ("" if state == "IDENTICAL" else f"   *** port says: {hb}"))
    for i in range(min(len(ob), len(pb)), max(len(ob), len(pb))):
        extra = ob[i] if len(ob) > len(pb) else pb[i]
        lines.append(f"  block {i} MISSING ON {'PORT' if len(ob) > len(pb) else 'ORACLE'}: "
                     f"{extra[0]}   *** A LOST STAGE IS NOT A BYTE DIFF ***")
    for name, a, b in (("stdout", oout, pout), ("stderr", oerr, perr)):
        ca, cb = canon(a.encode()), canon(b.encode())
        same = ca == cb
        lines.append(f"  {name}: {'IDENTICAL' if same else 'DIFFERS'} "
                     f"({len(a)} vs {len(b)} bytes)")
        if not same:
            lines.append(f"  --- {name} diff (oracle < / port >) ---")
            lines += [ln.decode(errors="replace") for ln in _hunks(ca, cb, show)]
    return lines


def _hunks(a: bytes, b: bytes, show: int) -> list[bytes]:
    import difflib
    d = list(difflib.unified_diff(a.decode(errors="replace").splitlines(),
                                  b.decode(errors="replace").splitlines(),
                                  "oracle", "port", lineterm="", n=1))
    return [f"    {ln}".encode() for ln in (d[:show * 4] or ["<no textual difference>"])]


# ------------------------------------------------------------------ the input sets
# `live` is THE REPOSITORY, and it is the run the migration rule is about. Everything else is a
# PLANT: the substrate moved out from under a stage, with not one byte of the port or the oracle
# edited, so each branch is COMPARED rather than argued about. No real `bend`, `cc`, `node` or `zsh`
# runs in any plant, and nothing is copied from the live tree -- every stub is a few lines, because
# a plant that copies the thing it is meant to displace cannot prove anything.
#
# **`live` SETS `E2E_ROOT` EXPLICITLY, AND THAT IS NOT OPTIONAL.** Left to its own `dirname $0`/../..,
# the oracle -- three levels deep, in `e2epy/` -- computes `ROOT` as `<repo>/.agents`, which EXISTS,
# so `cd "$ROOT"` succeeds and the gate proceeds in a directory that is not the repository. Measured:
# the first `live` run died at `…/.agents/.venv/bin/python: No such file or directory` and printed
# ONE line, `== 1/4 oracle`, before stopping -- and the port printed all eight stages, because the
# port resolves `ROOT` from its own `__file__`. That is FINDING 1, reproduced on the live tree.
SETS = {"live": ENV | {"E2E_ROOT": str(ROOT)}}
# `codes` is the exit status of, IN ORDER: stage 1's oracle, stage 4's gate, stage 5's ops_bend,
# stage 6's port mm, stage 7's run-f64. `bend` is how many `name=value` rows the
# stub compiler emits: 25 PASSES stage 2's `> 20 rows` denominator, 5 does not and drives the RETRY
# PATH to its `set -e` abort, 0 emits nothing and exits 0 -- which is the exact failure `bend_run`
# exists for, since bend stack-overflows on roughly one run in twenty and prints nothing.
# `hide` drops ONE tool from PATH, which is how the two availability SKIPs are reached: no `node` is
# stage 3's skip, and no `zsh` is stage 7's `rc 127` skip AND stage 6's plain `FAIL rc=127` -- an
# asymmetry in the shell, and the one place a missing tool is a failure in one stage and a skip in
# the next, so it is compared rather than tidied.
PLANTS = {
    "plant-pass":      dict(codes="0,0,0,0,0", bend=25),
    "plant-passskip":  dict(codes="0,0,0,0,3", bend=25),
    "plant-refuse":    dict(codes="0,0,1,1,3", bend=25),
    "plant-no-node":   dict(codes="0,0,0,0,0", bend=25, hide="node"),
    "plant-no-zsh":    dict(codes="0,0,0,0,0", bend=25, hide="zsh"),
    "plant-thin":      dict(codes="0,0,0,0,0", bend=5),
    "plant-deadbend":  dict(codes="0,0,0,0,0", bend=0),
    "plant-stage1red": dict(codes="3,0,0,0,0", bend=25),
}
# EVERY TOOL THE ORACLE ITSELF NEEDS, so a `hide` removes the ONE under test. A `hide` that also
# removed `grep` or `sed` would not be testing availability, it would be testing a broken plant.
SHELL_TOOLS = ("grep", "sed", "head", "tail", "cat", "mkdir", "sleep", "rm", "wc", "tr", "diff",
               "ls", "env", "chmod", "cp", "mv")
FX = ROOT / ".agents/slop/e2epy/fixtures"
# THE ORACLE SHEBANG IS `#!/bin/sh`, so `sh` IS ITS INTERPRETER -- see `compare` docstring.
SH = shutil.which("sh") or "/bin/sh"


def _real_node() -> str | None:
    """A node that is NOT `/Users/cyberistic/.nub/node-shim/node`, which is a Mach-O binary that
    probes for an installed node version on every invocation. Measured: it costs ~15 s per call,
    which is most of a 36 s plant, and a plant that spends its time probing node is a plant whose
    duration is not the thing under test. Falls back to `which node` so a machine with only the shim
    still gets a working sandbox."""
    for d in os.environ.get("PATH", "").split(os.pathsep):
        p = os.path.join(d, "node") if d else "node"
        if os.access(p, os.X_OK) and ".nub" not in p:
            return p
    return shutil.which("node")


def _build_plant(tag: str, spec: dict) -> Path:
    """The plant tree. `spec` says what every stage answers; the STUBS are the only thing in it."""
    fx = FX / tag
    if fx.exists():
        shutil.rmtree(fx)
    for sub in (".venv/bin", "bin", "sandbox", ".agents/slop/e2e_port", ".agents/slop/f64",
                ".agents/slop/jstage", "runs/e2e"):
        (fx / sub).mkdir(parents=True, exist_ok=True)
    codes = spec["codes"].split(",")

    def stub(name: str, body: str) -> None:
        p = fx / name
        p.write_text(body)
        p.chmod(0o755)

    stub(".venv/bin/python", f"""#!/bin/sh
# STUB for $ROOT/.venv/bin/python: it answers each of the scripts the gate runs with the exit code
# this plant names, and prints one identifiable line so the artifact shows which stub ran.
#
# IT ALSO PRINTS THE DENOMINATOR THE REAL GATE PRINTS, because `run-f64.sh`'s filter matching
# nothing on both sides would diff IDENTICAL and prove nothing, and a DENOMINATOR LINE is the same
# argument one level up: a plant whose stage reports no count cannot be counted by
# `e2estage8/verdicts.py`, so the census could never be shown to PASS on any artifact.
case "$1" in
  *e2e_mm.py)      echo "PLANT stub: stage1 oracle"; exit {codes[0]} ;;
  *e2e_mm_gate.py) echo "PLANT stub: stage4 gate, 20/20 rows vs CPython"
                    echo "mm_e2e_buffers=6"; echo "mm_e2e_out_words=64"; exit {codes[1]} ;;
  *)               echo "PLANT stub: $1"; exit 0 ;;
esac
""")
    stub("bin/bend", f"""#!/bin/sh
# STUB bend: {spec["bend"]} `name=value` rows, so stage 2's `> 20 rows` denominator is
# {'MET on attempt 1' if spec["bend"] > 20 else 'NOT met, so the run is retried 8 times'}.
i=0; while [ $i -lt {spec["bend"]} ]; do echo "PLANT.row$i=$i"; i=$((i+1)); done
exit 0
""")
    # `tail -3` KEEPS THREE LINES, so each of these stubs prints EXACTLY THREE: adding a fourth to
    # carry a denominator would silently drop the line that says which stub ran.
    stub(".agents/slop/opsbend-milestone.sh",
         f"#!/bin/sh\necho 'PLANT stub: stage5 ops_bend milestone'\n"
         f"echo '# 0 failed of 3 rows read'\necho 'PASS'\nexit {codes[2]}\n")
    stub(".agents/slop/e2e_port/run-port-mm.sh",
         f"#!/bin/sh\necho 'PLANT stub: stage6 port matmul, 64/64 words'\n"
         f"echo 'words port=64  CPython=64  differing lines=0  diff bytes=0'\n"
         f"echo 'STAGE 6 PASS'\nexit {codes[3]}\n")
    # `run-f64.sh` PRINTS THE LINES STAGE 7 FILTERS FOR, so stage 7's `grep -E` is compared and not
    # skipped: a filter that matches nothing on both sides would diff IDENTICAL and prove nothing.
    stub(".agents/slop/f64/run-f64.sh", f"""#!/bin/sh
echo 'PLANT stub: run-f64.sh'
[ {codes[4]} -eq 3 ] && echo 'REFUSED[ cold substrate: renderer/amd/generate.bend is 0 bytes ]'
[ {codes[4]} -eq 0 ] && {{ echo '   STAGE 7 PASS'; echo '   64/64 MET'; echo '   GREEN [C0]'; }}
echo '     F64-1 words_port=64'
exit {codes[4]}
""")
    box = fx / "sandbox"
    tools = {t: shutil.which(t) for t in SHELL_TOOLS}
    tools["node"], tools["zsh"] = _real_node(), shutil.which("zsh")
    for t, real in tools.items():
        if t != spec.get("hide") and real:
            (box / t).symlink_to(real)
    return fx


def main() -> int:
    ap = argparse.ArgumentParser(prog=__file__, description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sets", nargs="+", default=["live"], choices=sorted(SETS) + sorted(PLANTS),
                    help="input classes: the live repository, or a named plant")
    ap.add_argument("--show", type=int, default=6, help="diff hunks per stream")
    opts = ap.parse_args()
    ART.mkdir(parents=True, exist_ok=True)
    sets = {k: v for k, v in SETS.items() if k in opts.sets}
    for tag in [t for t in opts.sets if t in PLANTS]:
        fx = _build_plant(tag, PLANTS[tag])
        # THE SANDBOX PATH, plus the plant's `E2E_ROOT`. Both sides get the identical environment, so
        # the pair differs in exactly one thing: which program is reading it.
        sets[tag] = ENV | {"E2E_ROOT": str(fx), "PATH": f"{fx}/sandbox"}
    bad = []
    for tag in opts.sets:
        lines = compare(tag, sets[tag], opts.show)
        for ln in lines:
            print(ln)
        if any("DIFFERS" in ln or "***" in ln for ln in lines):
            bad.append(tag)
    print(f"\n{len(bad)} of {len(opts.sets)} set(s) disagree"
          + (f": {', '.join(bad)}" if bad else "")
          + f".  artifacts: {ART.relative_to(ROOT)}/")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
