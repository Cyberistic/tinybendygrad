#!/usr/bin/env python3
"""Reconstruct the `math.*` wall from the live tree.

WALLMAP.md cites a classifier named `MATH-LIB` that produced
  n_lines=31  n_files=12  n_targets=35
but the classifier itself was NOT preserved:

    $ rg -a -l 'MATH-LIB' .agents/
    .agents/slop/wallmap/rank.json
    .agents/slop/WALLMAP.md

So the 35 is a number without a reproducible instrument. This script re-derives
it under an explicitly stated rule so the number can be argued with.

THE RULE (stated so it can be wrong loudly):
  * a MARKER is a line matching  ^\\s*#\\s*TODO\\((p[0-9N]|delete)\\)
  * a BLOCK is the marker line plus every following line that is still a comment
    and carries no marker of its own  (WALLMAP's "own-block" rule)
  * a BLOCK is a math-block if its text contains `math.<ident>`
  * the TARGET is the upstream symbol the marker line names, i.e. the token
    after the upstream `file:line` -- for the `mixin/elementwise.bend` band that
    is the elementwise method name, for `uop/fold.bend` it is the ops.py symbol

Usage:  python3 .agents/slop/mathlib/reconstruct.py [--json]
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
PORT = ROOT / "tinybendygrad"

MARKER = re.compile(r"^\s*#\s*TODO\((?:p[0-9N]|delete)\)")
MATHREF = re.compile(r"math\.([A-Za-z_][A-Za-z_0-9]*)")
# upstream symbol:  `file.py:123  def name`  or  `file.py:123  name`
UPSTREAM = re.compile(r"([A-Za-z_][\w/]*\.py):(\d+)\s+(?:def\s+)?([A-Za-z_][\w]*)")


def blocks(path: pathlib.Path):
    """Yield (marker_lineno, marker_text, block_text) for every marker in path."""
    lines = path.read_text(errors="replace").splitlines()
    for i, ln in enumerate(lines):
        if not MARKER.match(ln):
            continue
        j = i + 1
        while j < len(lines):
            nxt = lines[j]
            if MARKER.match(nxt):
                break
            # continuation must be a comment, otherwise the block ended
            if nxt.strip() and not nxt.lstrip().startswith("#"):
                break
            j += 1
        yield i + 1, ln, "\n".join(lines[i:j])


def main() -> int:
    rows = []
    for f in sorted(PORT.rglob("*.bend")):
        try:
            for lineno, marker, block in blocks(f):
                m = MATHREF.search(block)
                if not m:
                    continue
                up = UPSTREAM.search(marker)
                rows.append({
                    "file": str(f.relative_to(ROOT)),
                    "line": lineno,
                    "marker": marker.strip(),
                    "math": sorted(set(MATHREF.findall(block))),
                    "upstream": up.group(0) if up else None,
                    "target": up.group(3) if up else None,
                })
        except OSError:
            pass

    targets = {r["target"] for r in rows if r["target"]}
    files = {r["file"] for r in rows}
    summary = {
        "n_block_lines": len(rows),
        "n_files": len(files),
        "n_distinct_targets": len(targets),
        "n_rows_without_upstream": sum(1 for r in rows if not r["upstream"]),
    }
    if "--json" in sys.argv:
        json.dump({"summary": summary, "rows": rows}, sys.stdout, indent=1)
        print()
        return 0

    print(json.dumps(summary, indent=1))
    print()
    for r in rows:
        print(f"{r['file']}:{r['line']}  {','.join(r['math']):<28} "
              f"{r['target'] or '(no upstream symbol)'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())