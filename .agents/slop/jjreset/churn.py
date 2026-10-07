"""Measure this tree's NORMAL deletion churn per commit, to PICK the guard's threshold
from the data instead of guessing it.

For each of the last N commits, count files with status D (deleted) and total deleted
LINES. The catastrophe (61be7ea90: 6168 files) and its recovery sit at the top; the
question the guard answers is "is this commit's deletion count still inside the
envelope of commits this tree actually makes?"

Run:  .venv/bin/python .agents/slop/jjreset/churn.py
Writes: .agents/slop/jjreset/churn.rows
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
N = 120


def git(*args):
    return subprocess.run(["git", "--no-optional-locks", "-C", str(ROOT), *args],
                          capture_output=True, text=True, check=True).stdout


def stat(sha):
    """(deleted_files, deleted_lines, total_files) for one commit, relative to its parent."""
    out = git("diff-tree", "-r", "--numstat", "--no-commit-id", sha)
    delf = lines = tot = 0
    for ln in out.splitlines():
        parts = ln.split("\t")
        if len(parts) != 3:
            continue
        add, dele, path = parts
        tot += 1
        if dele == "-":            # binary
            continue
        if int(dele) > 0:
            lines += int(dele)
        # a path counts as DELETED when it is gone from this commit
    return delf, lines, tot


def deleted_paths(sha):
    out = git("diff-tree", "-r", "--name-status", "--no-commit-id", sha)
    return [l.split("\t", 1)[1] for l in out.splitlines() if l.startswith("D\t")]


def main():
    shas = git("log", "--format=%H", f"-{N}").split()
    rows = []
    for sha in shas:
        dfs = deleted_paths(sha)
        _, dl, tf = stat(sha)
        rows.append((sha[:9], len(dfs), dl, tf))
    rows.sort(key=lambda r: r[1])
    lines = ["commit\tdeleted_files\tdeleted_lines\ttouched_files"]
    lines += [f"{s}\t{f}\t{dl}\t{tf}" for s, f, dl, tf in rows]
    (Path(__file__).parent / "churn.rows").write_text("\n".join(lines) + "\n")
    # the envelope: ignore the two catastrophe/recovery commits, report the max among the rest
    normal = [r for r in rows if r[1] < 1000]
    print(f"commits measured: {len(rows)}")
    print(f"max deleted_files  (normal, <1000): {max(r[1] for r in normal)}")
    print(f"max deleted_files  (all):           {max(r[1] for r in rows)}")
    print(f"max deleted_lines  (normal, <1000 files): {max(r[2] for r in normal)}")
    print(f"max deleted_lines  (all):           {max(r[2] for r in rows)}")
    print("top 10 by deleted_files:")
    for s, f, dl, tf in rows[-10:][::-1]:
        print(f"  {s}  files={f:5d}  lines={dl:8d}  touched={tf}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
