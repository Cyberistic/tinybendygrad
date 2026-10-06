#!/usr/bin/env python3
"""Static proof for the ADEV renderer fix: WHICH py-side rows move, over the WHOLE corpus.

`bend` is not run. Both sides here are CPython: the worktree `graphcmp.py` (post-fix) and the
same file at `HEAD` (pre-fix, extracted with `git show`). A normal-form change is about OUTPUT
TEXT, so the only honest static check is to emit both and diff the text.

    .venv/bin/python .agents/slop/adevfix/emit_diff.py

Prints one line per graph whose py rows moved, then the moved rows. A graph in NEITHER list
emitted byte-identical rows.
"""
from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parents[3]
CUR = REPO / ".agents" / "slop" / "graphcmp.py"
PY = REPO / ".venv" / "bin" / "python"


def rows(script: pathlib.Path, graph: str) -> list[str]:
    r = subprocess.run([str(PY), str(script), "emit", "--side", "py", "--graph", graph],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return [f"<RC={r.returncode}> {r.stderr.strip()[:200]}"]
    return r.stdout.splitlines()


def main() -> int:
    sys.path.insert(0, str(REPO / ".agents" / "slop"))
    import graphcmp as G

    tmp = pathlib.Path(tempfile.mkdtemp())
    head = tmp / "graphcmp_head.py"
    head.write_text(subprocess.run(["git", "show", "HEAD:.agents/slop/graphcmp.py"],
                                   cwd=REPO, capture_output=True, text=True).stdout)
    moved = []
    for g in sorted(G.GRAPHS):
        a, b = rows(head, g), rows(CUR, g)
        if a != b:
            moved.append((g, a, b))
    print(f"# graphs: {len(G.GRAPHS)}; py-side graphs whose rows moved: {len(moved)}")
    for g, a, b in moved:
        print(f"\n## {g}")
        for i, (x, y) in enumerate(zip(a, b), 1):
            mark = "  " if x == y else "**"
            print(f"  {i}{mark} HEAD : {x}")
            if x != y:
                print(f"   {mark} FIX  : {y}")
    return 0 if len(moved) == 1 and moved[0][0] == "allred" else 1


if __name__ == "__main__":
    raise SystemExit(main())
