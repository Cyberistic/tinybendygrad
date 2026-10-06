"""Resolve, for each of the 201 empty captures, its PRODUCER write site.

A producer must be an executable/script file (.py/.sh/.bend/.mjs/.js/.ts) whose
text references the capture path AND whose line looks like a WRITE, not a read
or a prose mention. Census artifacts (emptyblob/, residue/, unknowns/,
stale71/, _cite/, *.sha256, *.filelist, *.md reports) are excluded by shape:
a checker lists paths, a producer writes them.
"""
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent

CODE_EXT = {".py", ".sh", ".bend", ".mjs", ".js", ".ts", ".mk", ".yml", ".yaml"}
# a path reciting a directory of enumeration is census, not production
CENSUS_DIRS = (
    "emptyblob/", "residue/", "unknowns/", "stale71/", "_cite/",
    "oracles259/", "agend/", "emptyevid/", "gendirs/", "txt259/",
    "restorekit/", "needsaudit/", "tree-verdict",
)

WRITE_PAT = re.compile(
    r"(?:>>?|tee\b|2>>?|&>|>\|)"          # redirection
    r"|(?:\.write_text|\.write_bytes|open\([^)]*['\"]w)"
    r"|(?:set -o noclobber)"
)
# lines that are clearly a read or a hash manifest
READ_PAT = re.compile(r"(?:cat|head|tail|grep|wc|sha256|diff|cmp|read)\b")


def looks_write(text: str) -> bool:
    return bool(WRITE_PAT.search(text))


def main():
    prod = json.loads((HERE / "producers.json").read_text())
    resolved = {}
    for path, hits in prod.items():
        cand = []
        for h in hits:
            f = h["file"]
            if any(c in f for c in CENSUS_DIRS):
                continue
            if Path(f).suffix not in CODE_EXT:
                continue
            cand.append(h)
        resolved[path] = cand
    n_scripts = sum(1 for v in resolved.values() if v)
    n_write = sum(1 for v in resolved.values()
                  if any(looks_write(h["text"]) for h in v))
    print(f"captures: {len(prod)}")
    print(f"referenced by a script file (any suffix {sorted(CODE_EXT)}): {n_scripts}")
    print(f"referenced by a script with a write-like line:            {n_write}")
    print(f"NO script reference at all (ad-hoc/manifest only):        "
          f"{len(prod) - n_scripts}")
    # report per capture
    for path, cand in sorted(resolved.items()):
        ws = [h for h in cand if looks_write(h["text"])]
        if ws:
            for h in ws:
                print(f"WRITE {path}  <=  {h['file']}:{h['line']}  {h['text'][:90]}")
    (HERE / "script_refs.json").write_text(json.dumps(resolved, indent=2) + "\n")


if __name__ == "__main__":
    main()
