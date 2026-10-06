#!/usr/bin/env python3
"""census.py -- run EVERY corpus graph through one bend harness and the py oracle.

`.agents/slop/linfix/census.py <label> <gcmp.bend> <outdir>`. Each bend run goes
through `checks/bounded.py` and its VERDICT TOKEN is read, never its exit code; a
0-byte row file is DEAD, not a pass. Runs are SERIAL: `bend`'s precondition is the
SUM of the concurrently-running files' peak RSS (AGENTS.md), so no two at once.
"""
import pathlib
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[3]
BEND = REPO / "bin" / "bend"
BOUNDED = REPO / "checks" / "bounded.py"
PY = REPO / ".venv" / "bin" / "python"
GCMP = REPO / ".agents" / "slop" / "graphcmp.py"
GRAPHS = ["allred", "alu", "binblob", "bit", "buffer", "bw", "cast", "cdiv", "commute",
          "flip", "gate", "group", "indexed", "late", "lin", "loop", "matmul", "move",
          "range", "rangeflat", "reduce", "sink", "special", "sym", "where"]


def main() -> int:
    label, gcmp, out = sys.argv[1], pathlib.Path(sys.argv[2]).resolve(), pathlib.Path(sys.argv[3])
    (out / "py").mkdir(parents=True, exist_ok=True)
    for g in GRAPHS:
        b = subprocess.run([str(PY), str(BOUNDED), "--seconds", "900", "--mb", "2048", "--",
                            str(BEND), str(gcmp), g], cwd=REPO, capture_output=True, text=True)
        (out / f"{g}.rows").write_text(b.stdout)
        (out / f"{g}.err").write_text(b.stderr)
        row = [ln for ln in b.stdout.splitlines() if not ln.startswith("#")]
        tok = "WITHIN-LIMITS" if "WITHIN-LIMITS" in b.stderr else b.stderr.strip().splitlines()[-1][:40]
        if not row:
            print(f"{label}\t{g}\tDEAD\t0 rows\t{tok}")
            continue
        p = subprocess.run([str(PY), str(GCMP), "emit", "--side", "py", "--graph", g],
                           cwd=REPO, capture_output=True, text=True)
        (out / "py" / f"{g}.rows").write_text(p.stdout)
        pr = [ln for ln in p.stdout.splitlines() if ln.strip()]
        print(f"{label}\t{g}\tOK\tbend={len(row)} py={len(pr)}\t{tok}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
