#!/usr/bin/env python3
"""plants.py -- mutate ONE thing in the bend fixture (a DEVICE or the Opt) and
require `lin` to FAIL against the py oracle, on BOTH the pre-fix and post-fix
harnesses.

A plant is an ARMED mutation: the emitted row must MOVE and the row-for-row
comparison against `emit --side py` must NOT be 46/46. A mutation that leaves the
bytes alone is the DEFECT (`value-blind` below), not a plant, and is reported as
such. Each mutation is applied to the file IN PLACE in a try/finally, so a crash
cannot leave a mutated harness behind.
"""
import pathlib
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[3]
BEND = REPO / "bin" / "bend"
BOUNDED = REPO / "checks" / "bounded.py"
PY = REPO / ".venv" / "bin" / "python"
POST = REPO / ".agents" / "slop" / "graphcmp.bend"
PRE = REPO / ".agents" / "slop" / "linfix" / "before" / "drivers" / "two" / "gcmp.bend"
PYROWS = [l for l in (REPO / ".agents" / "slop" / "linfix" / "before-out" / "py" / "lin.rows")
          .read_text().splitlines() if l.strip()]

# the exact strings, each unique in its file
POST_DEVICE = ("nm, S.AGlobal{}, Some{S.D1{0}},", "nm, S.AGlobal{}, Some{S.D1{1}},")
PRE_DEVICE = ("nm, S.AGlobal{}, Some{S.D1{0}},", "nm, S.AGlobal{}, Some{S.D1{1}},")
POST_AXIS = ("O.SPL{0, O.AXIS_UPCAST{}, None{}}", "O.SPL{1, O.AXIS_UPCAST{}, None{}}")
PRE_COUNT = ('O.KernelInfo{"r_4_5_3", [0], None{}, 0}', 'O.KernelInfo{"r_4_5_3", [0, 0], None{}, 0}')
PRE_VALUE = ('O.KernelInfo{"r_4_5_3", [0], None{}, 0}', 'O.KernelInfo{"r_4_5_3", [7], None{}, 0}')

PLANTS = [
    ("PRE  device", PRE, *PRE_DEVICE, True),
    ("PRE  subject-count", PRE, *PRE_COUNT, True),
    ("PRE  value-blind", PRE, *PRE_VALUE, False),
    ("POST device", POST, *POST_DEVICE, True),
    ("POST subject-axis", POST, *POST_AXIS, True),
]


def rows(path: pathlib.Path) -> list[str]:
    b = subprocess.run([str(PY), str(BOUNDED), "--seconds", "900", "--mb", "2048", "--",
                        str(BEND), str(path), "lin"], cwd=REPO, capture_output=True, text=True)
    tok = "WITHIN-LIMITS" if "WITHIN-LIMITS" in b.stderr else "REFUSED"
    out = [l for l in b.stdout.splitlines() if not l.startswith("#")]
    return out, tok


def main() -> int:
    for name, path, old, new, armed in PLANTS:
        src = path.read_text()
        if src.count(old) != 1:
            print(f"{name}: target not unique ({src.count(old)}) -- SKIPPED")
            continue
        try:
            path.write_text(src.replace(old, new))
            got, tok = rows(path)
        finally:
            path.write_text(src)
        base = ([l for l in (REPO / ".agents" / "slop" / "linfix" / "after-out" / "lin.rows")
                .read_text().splitlines() if not l.startswith("#")] if path == POST else
                [l for l in (REPO / ".agents" / "slop" / "linfix" / "before-out" / "lin.rows")
                 .read_text().splitlines() if not l.startswith("#")])
        moved = got != base
        agree = sum(x == y for x, y in zip(PYROWS, got)) if len(got) == len(PYROWS) else -1
        verdict = "FAILS" if (agree != len(PYROWS)) else "PASSES"
        want = "ARMED -> must FAIL" if armed else "CONTROL -> must NOT move"
        ok = "OK" if ((moved and agree != len(PYROWS)) if armed else (not moved)) else "*** WRONG ***"
        print(f"{name:22} token={tok} rows={len(got)} moved={moved} agree={agree}/{len(PYROWS)} "
              f"{verdict} [{want}] {ok}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
