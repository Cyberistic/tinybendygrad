#!/usr/bin/env python3
"""demark.py -- strip the tree's old comment emphasis.

    .venv/bin/python .agents/slop/loc/demark.py <path>...
    .venv/bin/python .agents/slop/loc/demark.py --report <path>...

Two edits, on comment lines only, and both are pure deletions:

  * `**` goes, unless it sits between two digits -- `commit_int(2**32, ...)` is
    code in a comment, and stripping its exponent would corrupt the sample.
  * the arrow (U+21D2) becomes `-`, or disappears where it only opens a line.

The all-caps shout is NOT re-cased here, and the measurement is why. Measured
2026-11-11 on `tinybendygrad/uop/render.bend`: the block-level re-caser turned
`pretty_print` into `Pretty_print`, `lambda x:` into `Lambda x:` and
`cache.setdefault` into `Cache.setdefault` -- it carries case inside the Python
samples these comments hold -- and it capitalised every continuation line
("Room.", "Half that was cheap."). Case is meaning in this tree's comments, so
only a reader can lower it; this tool does the two edits a machine can prove.
"""

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

# The arrow's escape spelling, never the character: `fe413f5f1` removed the
# character from the tree and took the literal with it, so this module once read
# `b.replace(" ", "-")` and rewrote every space in every comment.
ARROW = "\u21D2"
STAR = "**"


def demark(body: str) -> str:
    out, i = [], 0
    while i < len(body):
        if body[i : i + 2] == STAR:
            prev = body[i - 1] if i else ""
            nxt = body[i + 2] if i + 2 < len(body) else ""
            if not (prev.isdigit() and nxt.isdigit()):
                i += 2
                continue
        out.append(body[i])
        i += 1
    text = "".join(out)
    # An arrow that opens a line marks the line; one mid-line is a connector.
    text = text.lstrip()
    if text.startswith(ARROW):
        text = text[1:].lstrip()
    return text.replace(ARROW, "-")


def rewrite(lines: list[str]) -> list[str]:
    out = []
    for line in lines:
        stripped = line.strip()
        if not stripped.startswith("#"):
            out.append(line)
            continue
        indent = line[: len(line) - len(line.lstrip())]
        body = stripped.lstrip("#").strip()
        new = demark(body)
        out.append(line if new == body else f"{indent}# {new}".rstrip())
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*", default=[])
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()
    if not args.files:
        print(__doc__)
        return 0

    total = 0
    for rel in args.files:
        path = Path(rel) if Path(rel).is_absolute() else ROOT / rel
        lines = path.read_text().split("\n")
        out = rewrite(lines)
        changed = sum(1 for a, b in zip(lines, out) if a != b)
        total += changed
        if args.report:
            for a, b in zip(lines, out):
                if a != b:
                    print(f"  {path}: {a.strip()[:100]}")
                    print(f"  {' ' * len(path.name)}  {b.strip()[:100]}")
        else:
            path.write_text("\n".join(out))
    print(f"  {total} lines changed", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
