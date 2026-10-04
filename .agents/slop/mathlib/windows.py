#!/usr/bin/env python3
r"""Window sensitivity: why `math.*` is 14, 20, 31 or 35 depending on the rule.

WALLMAP.md §3 reports `no math.*` as  n_lines=31  n_files=12  n_targets=35.
`reconstruct.py` under a stated own-block rule reports 16 / 7 / 14.

This script sweeps the four knobs that could carry the difference, so the gap is
attributable rather than mysterious:

  WINDOW   own   -- marker line + following comment lines with no marker
           next  -- marker line + everything up to the NEXT marker, unbounded
                     (this is `grw-census.py`'s rule; WALLMAP §7 says it
                      over-counts)
  PATTERN  tight -- the literal token `math.`
           loose -- `math.` OR one of the identifiers the markers use as a
                     synonym for it: `mathlib`, `MATH-LIB`, `gcd`, `1/math`,
                     `no \`math`, `float helper`

Run:  python3 .agents/slop/mathlib/windows.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
PORT = ROOT / "tinybendygrad"

MARKER = re.compile(r"^\s*#\s*TODO\((?:p[0-9N]|delete)\)")
TIGHT = re.compile(r"math\.[A-Za-z_]")
LOOSE = re.compile(r"math\.|mathlib|MATH-LIB|no math|float helper", re.I)
UPSTREAM = re.compile(r"([A-Za-z_][\w/]*\.py):(\d+)\s+(?:def\s+)?([A-Za-z_][\w]*)")
ANY_COMMENT = re.compile(r"^\s*#")


def window(lines: pathlib.Path, i: int, mode: str) -> str:
    if mode == "own":
        j = i + 1
        while j < len(lines):
            if MARKER.match(lines[j]):
                break
            if lines[j].strip() and not ANY_COMMENT.match(lines[j]):
                break
            j += 1
        return "\n".join(lines[i:j])
    j = i + 1
    while j < len(lines) and not MARKER.match(lines[j]):
        j += 1
    return "\n".join(lines[i:j])


def sweep() -> dict:
    corpus = {f: f.read_text(errors="replace").splitlines() for f in sorted(PORT.rglob("*.bend"))}
    out = {}
    for wmode in ("own", "next"):
        for pmode, pat in (("tight", TIGHT), ("loose", LOOSE)):
            rows = []
            for f, lines in corpus.items():
                for i, ln in enumerate(lines):
                    if not MARKER.match(ln):
                        continue
                    if not pat.search(window(lines, i, wmode)):
                        continue
                    up = UPSTREAM.search(ln)
                    rows.append((str(f.relative_to(ROOT)), i + 1, up.group(3) if up else None))
            out[f"{wmode}/{pmode}"] = {
                "n_lines": len(rows),
                "n_files": len({r[0] for r in rows}),
                "n_targets": len({r[2] for r in rows if r[2]}),
                "files": sorted({r[0] for r in rows}),
                "targets": sorted({r[2] for r in rows if r[2]}),
            }
    return out


def main() -> int:
    for k, v in sweep().items():
        print(f"{k:>10}  lines={v['n_lines']:>3}  files={v['n_files']:>2}  targets={v['n_targets']:>3}")
    print()
    print("WALLMAP.md §3 claims      lines= 31  files= 12  targets= 35")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())