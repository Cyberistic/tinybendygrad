"""Find producers of each empty capture by searching tracked files for the path.

A producer is a file whose text references the capture path. We search both the
full relative path and the unique basename (producers often build the path from
a variable). Hits are recorded with file:line and the line's text so a later
pass can tell a WRITE (redirect / open-for-write / write_text) from a READ.
"""
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def git_grep(pattern: str):
    """git grep -n -F for a fixed pattern; returns [(file, line, text)]."""
    if not pattern:
        return []
    p = subprocess.run(
        ["git", "grep", "-n", "-F", "--", pattern],
        cwd=ROOT, capture_output=True, text=True,
    )
    hits = []
    for ln in p.stdout.splitlines():
        f, _, rest = ln.partition(":")
        no, _, text = rest.partition(":")
        if not no.isdigit():
            continue
        hits.append((f, int(no), text))
    return hits


def main():
    pop = json.loads((HERE / "population.json").read_text())
    prior = {}
    for line in (HERE.parent / "emptyblob" / "EMPTY.tsv").read_text().splitlines()[1:]:
        c = line.split("\t")
        if len(c) >= 4:
            prior[c[0]] = c[3]
    sentinel = [r["path"] for r in pop["empty"]
                if prior.get(r["path"]) == "SENTINEL/UNKNOWN"]

    out = {}
    for path in sentinel:
        base = path.rsplit("/", 1)[-1]
        hits = {}
        for pat in {path, base}:
            for f, no, text in git_grep(pat):
                if f.startswith(".agents/slop/emptyevid/"):
                    continue
                hits.setdefault((f, no), text)
        out[path] = [{"file": f, "line": no, "text": t}
                     for (f, no), t in sorted(hits.items())]
    (HERE / "producers.json").write_text(json.dumps(out, indent=2) + "\n")
    named = sum(1 for v in out.values() if v)
    print(f"captures: {len(sentinel)}  with >=1 reference: {named}  "
          f"no reference: {len(sentinel) - named}")
    # distribution of exact-path references
    exact = 0
    for path in sentinel:
        if any(h["file"] and path in h["text"] for h in out[path]):
            exact += 1
    print(f"with a reference that recites the FULL path: {exact}")


if __name__ == "__main__":
    main()
