#!/usr/bin/env python3
"""THE THIRD FALSE-POSITIVE MODE, AND IT IS THE SAME SHAPE AS `Allocator` IN `BumpAllocator`.

`checks/citation-gate.py` takes **the LONGEST backtick span on the citation's own line** as the
quoted source. But a citation's line often carries SEVERAL spans, and the longest is not always the
one the citation is about:

    # `_render_fn` -- llvmir.py:156-160, the AMD barrier rule, and `_render_footer`.

`_render_footer` (16 chars) is longer than `_render_fn` (11), so the gate compares
`_render_footer` against `llvmir.py:156` -- which is `def _render_fn(...)` -- and reports
`STALE-LINE`, distance 53. **The citation is CORRECT. The gate quoted the wrong span.**

    .venv/bin/python .agents/slop/stale269/spans.py rows.tsv CLASS [SUBSTR]

For every row it re-runs the claim with **EACH** backtick span on the citation line and asks which
spans sit on the cited line IN THE BLOB. If the gate's chosen span does NOT, and another span on
the same line DOES, the row is `QUOTE-MISCHOSEN`: not a broken citation, and not to be restored.

This is the `abi4_gate.py` trap one level up: `dtype: S.Dt` passes a pin meant for `S.Dt`, and
`_render_footer` passes a pin meant for `_render_fn`. **Both are a substring pin accepting a
sibling.** A gate that takes the longest span is a gate that will, on some row, take the wrong one.
"""
import importlib.util
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
_s = importlib.util.spec_from_file_location("citation_gate", os.path.join(ROOT, "checks/citation-gate.py"))
G = importlib.util.module_from_spec(_s)
_s.loader.exec_module(G)
QUOTE = re.compile(r"`([^`\n]{8,400})`")   # the GATE'S OWN regex, imported, not a second one
CITE = re.compile(r"(?<![\w./-])((?:[\w.-]+/)*[\w.-]+\.py):(\d+)(?:-(\d+))?")


def show(commit: str, path: str) -> str | None:
    r = subprocess.run(["git", "show", f"{commit}:{path}"], cwd=ROOT, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def port_history(port: str, line: int) -> list[str]:
    r = subprocess.run(["git", "log", "-L", f"{line},{line}:{port}", "--format=%h"],
                       cwd=ROOT, capture_output=True, text=True)
    return [c for c in r.stdout.split() if re.fullmatch(r"[0-9a-f]{7,}", c)]


def main(argv: list[str]) -> int:
    rows = open(argv[1], encoding="utf-8").read().splitlines()[1:]
    want = argv[2]
    idx = G.python_files()
    bad = tot = 0
    for f in rows:
        cls, port, pl, name, cl, near, dist, occ, other, quote = f.split("\t")
        if cls != want:
            continue
        tgt = G.resolve(name, port, idx)
        if tgt is None:
            continue
        rp = os.path.relpath(tgt, ROOT)
        src = open(os.path.join(ROOT, port), encoding="utf-8").read().splitlines()
        line = src[int(pl) - 1]
        m = next((c for c in CITE.finditer(line) if c.group(1) == name and c.group(2) == cl), None)
        if m is None:
            continue
        spans = QUOTE.findall(line)
        if len(spans) < 2 or quote not in spans:
            continue  # only the multi-span lines can be mis-chosen
        tot += 1
        blob = hb = None
        for c in port_history(port, int(pl)):
            b = show(c, rp)
            if b is not None:
                blob, hb = c, b
                break
        if hb is None:
            continue
        bl = hl = hb.splitlines()
        lo = int(cl)
        hi = int(m.group(3)) if m.group(3) else lo
        inside = [s for s in spans
                  if any(s in bl[n - 1] for n in range(max(1, lo - 2), min(len(bl), hi + 2) + 1))]
        if quote in inside:
            continue  # the gate's own choice is one of the spans that IS there
        bad += 1
        print(f"\nQUOTE-MISCHOSEN  {port}:{pl}  {rp}:{cl}{'-' + m.group(3) if m.group(3) else ''}")
        print(f"  CLAIM   {line.strip()[:175]}")
        print(f"  gate used   `{quote}`  -> NOT on the cited line in {blob}")
        for s in inside:
            print(f"  ON THE LINE `{s}`  -> at {rp}:{[n for n in range(max(1, lo-2), min(len(bl), hi+2)+1) if s in bl[n-1]][:4]}")
        for n in range(max(1, lo - 1), min(len(bl), hi + 1) + 1):
            print(f"    {rp}@{blob}:{n}  {bl[n - 1].strip()[:150]}")
    print(f"\n  {bad} of {tot} multi-span rows are QUOTE-MISCHOSEN", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))