"""Re-derive the empty-blob population from `git ls-tree -r HEAD`.

Population by DISCOVERY, not by a list: git's own tree, filtered by the empty
blob SHA. `git ls-files -s` is NOT used -- it answers the empty blob for
`git add -N` placeholders and inflated this to 1252 once.
"""
import json
import subprocess
import sys
from pathlib import Path

EMPTY = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]  # .agents/slop/emptyevid -> repo root


def ls_tree(rev="HEAD"):
    """Yield (mode, sha, path) for the whole tracked tree at `rev`."""
    out = subprocess.run(
        ["git", "ls-tree", "-r", rev],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout
    for line in out.splitlines():
        meta, _, path = line.partition("\t")
        mode, _type, sha = meta.split()
        yield mode, sha, path


def main():
    rev = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
    rev = subprocess.run(["git", "rev-parse", rev], cwd=ROOT,
                         capture_output=True, text=True, check=True).stdout.strip()
    rows = [(mode, sha, path) for mode, sha, path in ls_tree(rev)]
    empties = [(path, sha) for mode, sha, path in rows
               if mode == "100644" and sha == EMPTY]
    summary = {
        "head": rev,
        "tracked_paths": len(rows),
        "empty_blob": len(empties),
    }
    (HERE / "population.json").write_text(json.dumps(
        {"summary": summary,
         "empty": [{"path": p, "sha": s} for p, s in empties]},
        indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
