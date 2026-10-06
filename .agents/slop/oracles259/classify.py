#!/usr/bin/env python3
"""Classify oracles/*.txt by WHAT IS INSIDE, using three mechanisms that share no regex.

M1  shape: hand-written row-dump predicate (key=value on nearly every line).
M2  corpus-derived: same statistic computed over the 35 blessed .rows files, threshold
    derived from that population. No hand-written pattern; the shape is LEARNED.
M3  language: `file --mime-type` plus shebang / bend / python marker scan. Catches a
    source file wearing a .txt suffix -- the case M1 and M2 both call "rows".
"""
import json
import pathlib
import subprocess
import sys
from collections import Counter

ROOT = pathlib.Path("oracles")


def txt_files():
    return sorted(p for p in ROOT.rglob("*.txt") if p.is_file())


def rows_files():
    return sorted(p for p in ROOT.rglob("*.rows") if p.is_file())


def stat(lines):
    """Fraction of non-blank lines shaped `key=value`. Pure counting, no regex."""
    live = [ln for ln in lines if ln.strip()]
    if not live:
        return 0.0, 0
    hits = 0
    for ln in live:
        i = ln.find("=")
        if i <= 0:
            continue
        key = ln[:i]
        if all(c.isalnum() or c in "_.:/()[]<>+-*" for c in key) and not key[0].isspace():
            hits += 1
    return hits / len(live), len(live)


def stat_json(lines):
    """Fraction of the WHOLE FILE that parses as one JSON value."""
    text = "\n".join(lines)
    try:
        json.loads(text)
        return True
    except Exception:
        return False


def mime(path):
    out = subprocess.run(["file", "-b", "--mime-type", str(path)], capture_output=True, text=True)
    return out.stdout.strip()


SRC_MIME = ("x-shellscript", "x-python", "text/x-python", "x-executable", "x-perl", "x-ruby")


def mime_is_source(m):
    return any(m.startswith(p) for p in SRC_MIME)


def main():
    txts = txt_files()
    rows = rows_files()

    # M2: learn the shape from the blessed corpus.
    blessed = [(str(p), *stat(p.read_text(errors="replace").splitlines())) for p in rows]
    blessed_fracs = [f for _, f, _ in blessed]
    thr = min(blessed_fracs) if blessed_fracs else 1.0
    print(f"M2: {len(blessed)} blessed .rows files, min key=value fraction = {thr:.4f}", file=sys.stderr)
    for name, f, n in blessed:
        if f < thr:
            print(f"  BELOW-MIN {name} {f:.4f} n={n}", file=sys.stderr)

    groups = Counter()
    rowsout = []
    for p in txts:
        text = p.read_text(errors="replace")
        lines = text.splitlines()
        frac, nlive = stat(lines)
        m = mime(p)
        head = text[:400]
        is_json = stat_json(lines)
        shebang = lines[0].startswith("#!") if lines else False
        bendy = ("\ndef " in text or text.startswith("def ")) and "  " not in text[:200]

        # verdict per mechanism, then the group is the agreement
        m1 = frac >= 0.9
        m2 = frac >= thr
        m3 = mime_is_source(m) or shebang or is_json
        if is_json:
            g = "json-value"
        elif shebang or mime_is_source(m):
            g = "source-script"
        elif m1 and m2:
            g = "rowdump"
        elif m2 and not m1:
            g = "rowdump-mostly"
        elif m1 and not m2:
            g = "rowdump-near-miss"
        else:
            g = "other"
        groups[g] += 1
        rowsout.append(
            dict(
                path=str(p),
                bytes=len(text.encode()),
                lines=len(lines),
                kv_frac=round(frac, 4),
                mime=m,
                json=is_json,
                shebang=shebang,
                bendy=bendy,
                group=g,
            )
        )

    pathlib.Path(".agents/slop/oracles259/classified.json").write_text(json.dumps(rowsout, indent=1))
    print(json.dumps(groups, indent=1))
    for g in groups:
        print(f"\n===== {g} =====")
        for r in rowsout:
            if r["group"] == g:
                print(f'  {r["path"]:60s} {r["bytes"]:>9d}B {r["lines"]:>6d}L kv={r["kv_frac"]:.3f} {r["mime"]}')


main()
