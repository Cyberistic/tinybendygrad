#!/usr/bin/env python3
"""Plants for checks/sb-gate.sh: the fixed gate must go RED on each of them.

A gate that has only ever been seen green is a gate nobody has watched fail, and
gates/README.md's whole subject is gates that were. So each arm below asserts an
EXIT STATUS, and the harness fails if the gate returns 0 for a state it must not.

The tree is a THROW-AWAY COPY under $TMPDIR with a STUB ./bin/bend, so no real
`bend` runs and the live tree is never written. The gate is exercised exactly as
shipped -- it is copied, not edited, except for the one arm that deliberately
breaks its own `cd`.

    .venv/bin/python .agents/slop/sbgate/plant.py
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
GATE = REPO / "checks/sb-gate.sh"
TMP = Path(os.environ.get("TMPDIR", "/tmp"))

# A stub bend. $MODE decides what the "compiler" does, so each arm can make the
# port succeed, fail, emit nothing, or eat memory.
STUB_BEND = """#!/bin/sh
case "$SBG_MODE" in
  rows)    printf 'sb.rule.alpha=1\\nsb.rule.beta=2\\nsb.rule.gamma=3\\n'; exit 0 ;;
  drop)    printf 'sb.rule.alpha=1\\nsb.rule.beta=2\\n'; exit 0 ;;
  differ)  printf 'sb.rule.alpha=1\\nsb.rule.beta=999\\nsb.rule.gamma=3\\n'; exit 0 ;;
  norows)  exit 0 ;;
  dies)    echo 'error: no def named sb_rule' >&2; exit 1 ;;
  bomb)    perl -e 'my @a; while (1) { push @a, ("x" x 1_000_000) }' ;;
esac
"""

# The oracle and differ are PLANT FIXTURES, not the real ones -- they do not exist
# in this tree (see sb-gate.sh's header). A plant only has to make the gate reach
# its comparison arm and then disagree with it. The gate runs both with
# `.venv/bin/python`, so these are Python.
STUB_ORACLE = """\
print("sb.rule.alpha=1")
print("sb.rule.beta=2")
print("sb.rule.gamma=3")
"""
STUB_DIFFER = """\
import sys
a, b = open(sys.argv[1]).readlines(), open(sys.argv[2]).readlines()
rows = [f"< {x}" for x in a if x not in b] + [f"> {x}" for x in b if x not in a]
sys.stdout.writelines(rows)
sys.exit(1 if rows else 0)
"""


def build_tree(root: Path) -> Path:
    """A repo-shaped tree with a stub bend and stub fixtures. Nothing real is touched."""
    d = root / "tree"
    (d / "checks").mkdir(parents=True)
    (d / ".agents/slop/schedule-bodies").mkdir(parents=True)
    (d / "tinybendygrad/uop").mkdir(parents=True)
    (d / "tinybendygrad/schedule").mkdir(parents=True)

    shutil.copy(GATE, d / "checks/sb-gate.sh")
    shutil.copy(REPO / "checks/bounded.py", d / "checks/bounded.py")
    os.symlink(REPO / ".venv", d / ".venv")

    bend = d / "bin/bend"
    bend.parent.mkdir(parents=True)
    bend.write_text(STUB_BEND)
    bend.chmod(0o755)

    (d / "tinybendygrad/helpers.bend").write_text("# stub substrate\n")
    (d / "tinybendygrad/uop/ops.bend").write_text("# stub substrate\n")
    (d / "tinybendygrad/schedule/__init__.bend").write_text("# stub port\n")

    sb = d / ".agents/slop/schedule-bodies"
    (sb / "BEFORE-rows.txt").write_text("sb.rule.alpha=1\nsb.rule.beta=2\nsb.rule.gamma=3\n")
    (sb / "sb-oracle.py").write_text(STUB_ORACLE)
    (sb / "sb-diff.py").write_text(STUB_DIFFER)
    return d


def run(tree: Path, *argv: str, mode: str = "rows") -> tuple[int, str]:
    env = {**os.environ, "SBG_MODE": mode, "TMPDIR": str(TMP)}
    p = subprocess.run(["sh", "checks/sb-gate.sh", *argv], cwd=tree, env=env,
                       capture_output=True, text=True, timeout=120)
    return p.returncode, p.stdout + p.stderr


# (name, expected_exit, mode, what the gate is required to do)
ARMS = [
    ("clean tree, port agrees", 0, "rows", "the only arm allowed to be green"),
    ("port DROPS a floor row", 1, "drop", "the regression floor must catch it"),
    ("port DISAGREES with CPython", 1, "differ", "the differ's rc must decide"),
    ("baseline ABSENT", 3, "rows", "a missing baseline is not a passing baseline"),
    ("oracle ABSENT", 3, "rows", "no oracle, no verdict"),
    ("differ ABSENT", 3, "rows", "no differ, no verdict"),
    ("port emits NO ROWS", 3, "norows", "zero rows is not an answer"),
    ("port DIES", 3, "dies", "a dead port is not a row census"),
    ("port KILLED ON MEMORY", 3, "bomb", "a kill proves nothing"),
]

# NOT COVERED, and listed so the denominator is honest. The gate hardcodes
# --seconds 900, so exercising the TIMED-OUT arm means a 900 s wait or an edit to
# the gate under test. It is left uncovered rather than counted as covered by the
# memory arm, which shares the token-parsing arm but not the message.
UNCOVERED = ["port TIMED OUT (gate hardcodes --seconds 900; not exercised)"]


def main() -> int:
    root = Path(tempfile.mkdtemp(prefix="sbgate-plant.", dir=str(TMP)))
    failures = 0
    print(f"DENOMINATOR: {len(ARMS)} plants + 1 cd plant, {len(UNCOVERED)} NOT covered\n")
    print(f"{'arm':<32} {'want':>4} {'got':>4}  ")
    print("-" * 62)
    try:
        tree = build_tree(root)
        for name, want, mode, why in ARMS:
            if name == "baseline ABSENT":
                (tree / ".agents/slop/schedule-bodies/BEFORE-rows.txt").unlink()
            if name == "oracle ABSENT":
                (tree / ".agents/slop/schedule-bodies/sb-oracle.py").unlink()
            if name == "differ ABSENT":
                (tree / ".agents/slop/schedule-bodies/sb-diff.py").unlink()
            rc, out = run(tree, mode=mode)
            ok = rc == want
            failures += not ok
            first = next((l for l in out.splitlines() if l.strip()), "")
            print(f"{name:<32} {want:>4} {rc:>4}  {'ok ' if ok else 'LIES'}  {why}")
            if not ok:
                print(f"      first line: {first}")

        # THE cd PLANT: revert the one line that caused the original defect and show
        # that the gate now notices instead of printing `helpers= ops=` and exiting 0.
        g = tree / "checks/sb-gate.sh"
        g.write_text(g.read_text().replace('cd "$(dirname "$0")/.."', 'cd "$(dirname "$0")/../../.."'))
        rc, out = run(tree, mode="rows")
        ok = rc == 3 and "cd landed outside the repo" in out
        failures += not ok
        print(f"{'cd reverted to ../../..':<32} {3:>4} {rc:>4}  {'ok ' if ok else 'LIES'}  "
              f"the original defect, detected")
        if not ok:
            print(f"      output: {out[:200]}")
    finally:
        shutil.rmtree(root, ignore_errors=True)

    print(f"\n{'ALL PLANTS FIRED' if not failures else f'{failures} PLANT(S) DID NOT FIRE'}")
    for u in UNCOVERED:
        print(f"   NOT COVERED: {u}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())