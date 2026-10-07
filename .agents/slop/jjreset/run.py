"""Run the mass-delete gate's two states plus the real-tree readings, and capture every
token and exit code to artifacts. Read-only on the real tree: `check`/`staged` never write.

Run:  .venv/bin/python .agents/slop/jjreset/run.py
Writes: plant.out, plant.err, verdicts.rows
"""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
GATE = HERE / "git-massdelete-gate.py"
PY = sys.executable
ROOT = HERE.parents[2]


def run(args, stdin=None):
    return subprocess.run([PY, str(GATE), *args], capture_output=True, text=True,
                          input=stdin, cwd=ROOT)


def main():
    # --- plant: the two states, in a scratch repo ---
    p = run(["--plant"])
    (HERE / "plant.out").write_text(p.stdout)
    (HERE / "plant.err").write_text(p.stderr)
    assert "REFUSED, NOT A VERDICT" in p.stderr, "the 6000-file state did not REFUSE"
    assert "all states OK" in p.stdout, "a plant state failed"
    assert p.returncode == 0

    # --- the real tree, read-only ---
    rows = ["commit\tfiles\tlines\tverdict\trc"]
    for sha in ("61be7ea90",       # the catastrophe: 6167 files recorded deleted
                "813bbec3e",       # the recovery: 0 deletions, 6141 additions
                "a808071e8",       # the largest LEGITIMATE delete: 146 files / 237256 lines
                "baa109329",       # the git-add-A .txt sweep: 15 files
                "9d44f2c63",       # a normal small commit
                "949cea833"):      # HEAD
        r = run(["check", sha])
        tok = r.stdout.splitlines()[0] if r.stdout else r.stderr.splitlines()[0]
        verdict = tok.split(":")[0]
        # the gate prints "N files / M lines" -- read them back, do not recompute
        import re
        m = re.search(r"deletes (\d+) files / (\d+) lines", r.stdout + r.stderr)
        files, lines = (m.group(1), m.group(2)) if m else ("?", "?")
        rows.append(f"{sha}\t{files}\t{lines}\t{verdict}\t{r.returncode}")

    # --- staged: the index against HEAD ---
    s = run(["staged"])
    rows.append(f"staged\t-\t-\t{s.stdout.splitlines()[0].split(':')[0]}\t{s.returncode}")

    (HERE / "verdicts.rows").write_text("\n".join(rows) + "\n")
    print("\n".join(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
