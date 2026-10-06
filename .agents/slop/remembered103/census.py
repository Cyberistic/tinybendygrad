#!/usr/bin/env python3
"""The DENOMINATOR: every `103` the tree owns, and whether each is the declared-count.

`103` elsewhere is not the same defect. A census that counts tokens and calls them all one
bug grows a false positive, so every hit is classified against the subject: the size of
`differ.declared()`. Vendored upstream (`tinygrad/`) and the trees `checks/no-txt.py` already
skips are counted separately and not walked for classification.
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
SKIP = {".git", ".jj", "references", "node_modules", "__pycache__", ".venv"}
SKIP_PREFIX = ("tinygrad",)
TOKEN = re.compile(r"\b103\b")
# A hit is about THIS population when its line names the graphcmp declared `.txt` set. Everything
# else is a line number, a byte offset, an enum member, or a count of something else entirely.
POP = re.compile(r"writes all 103|declared|graphcmp|\b103\b[^|]*artifact|103 of 103|103 names"
                 r"|103 `?\.txt", re.I)
# A copy of the driver inside a fixture tree -- the stale sentence carried by a SNAPSHOT, not the
# tree's own source. `checks/differ.py` is the only LIVE owner.
SHADOW = re.compile(r"\.agents/slop/.*(checks/differ|differ.*dummy|differ\.py\.orig)")


def owned(rel: str) -> bool:
    parts = rel.split(os.sep)
    return not (set(parts) & SKIP or any(p.startswith(SKIP_PREFIX) for p in parts))


def main() -> int:
    pop, shadow, record, other, vendored, binary = [], [], [], [], 0, 0
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP]
        for f in filenames:
            path = os.path.join(dirpath, f)
            rel = os.path.relpath(path, ROOT)
            try:
                raw = open(path, "rb").read()
            except OSError:
                continue
            if b"\x00" in raw:  # a binary that happens to contain the bytes "103"
                binary += 1
                continue
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError:
                continue
            for i, line in enumerate(text.splitlines(), 1):
                if not TOKEN.search(line):
                    continue
                rec = (rel, i, line.strip()[:110])
                if rel.startswith("tinygrad" + os.sep):
                    vendored += 1
                elif not POP.search(line):
                    other.append(rec)
                elif SHADOW.search(rel):
                    shadow.append(rec)
                elif rel.endswith((".md", ".out", ".tsv", ".rows")) or rel.startswith(".agents/"):
                    record.append(rec)
                else:
                    pop.append(rec)
    pop = pop + shadow + record
    total = len(pop) + len(other) + vendored + binary
    print(f"# DENOMINATOR  `\\b103\\b` occurrences walked: {total}")
    print(f"#   ABOUT THIS POPULATION (graphcmp `declared()` `.txt` size): {len(pop)}")
    print(f"#     live source/docs  : {len(pop) - len(shadow) - len(record)}")
    print(f"#     fixture snapshots : {len(shadow)}")
    print(f"#     records/ledgers   : {len(record)}")
    print(f"#   UNRELATED (byte offsets, line numbers, other counts) owned : {len(other)}")
    print(f"#   VENDORED upstream `tinygrad/`                                : {vendored}")
    print(f"#   BINARY files carrying the bytes `103`                        : {binary}")
    for rel, i, line in pop:
        bucket = "shadow" if SHADOW.search(rel) else ("record" if rel.endswith(
            (".md", ".out", ".tsv", ".rows")) or rel.startswith(".agents/") else "LIVE")
        print(f"  {bucket:7} {rel}:{i}  {line}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
