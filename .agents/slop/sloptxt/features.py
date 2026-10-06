#!/usr/bin/env python3
"""Enumerate every owned `.txt` by DISCOVERY and dump content features. No basename logic.

`no-txt.py`'s ownership rule is reproduced here so the denominator is re-derived, not trusted.
Features are pure counts over the BYTES; no filename is ever consulted for a class.
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SKIP = {".git", "references", "node_modules", "__pycache__"}
SKIP_PREFIX = ("tinygrad", ".venv", "node_modules")
GRAPH_D = "runs/graphcmp/D"


def owned(rel: str) -> bool:
    parts = rel.split(os.sep)
    return not (set(parts) & SKIP or any(p.startswith(SKIP_PREFIX) for p in parts))


def find_txt():
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP]
        for f in filenames:
            if f.endswith(".txt"):
                rel = os.path.relpath(os.path.join(dirpath, f), ROOT)
                if owned(rel):
                    yield rel


def shape(line: str) -> str:
    """Structural shape: every run of word-chars -> W, digits -> D, punctuation kept."""
    out = []
    i = 0
    while i < len(line):
        c = line[i]
        if c.isdigit():
            out.append("D")
            while i < len(line) and line[i].isdigit():
                i += 1
        elif c.isalpha() or c == "_":
            out.append("W")
            while i < len(line) and (line[i].isalnum() or line[i] == "_"):
                i += 1
        elif c.isspace():
            out.append(" ")
            while i < len(line) and line[i].isspace():
                i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out).strip()


def kv_frac(lines):
    live = [ln for ln in lines if ln.strip()]
    if not live:
        return 0.0
    hits = 0
    for ln in live:
        i = ln.find("=")
        if i <= 0:
            continue
        key = ln[:i]
        if all(c.isalnum() or c in "_.:/()[]<>+-*" for c in key) and not key[0].isspace():
            hits += 1
    return hits / len(live)


def feature(path):
    raw = open(path, "rb").read()
    text = raw.decode("utf-8", errors="replace")
    lines = text.splitlines()
    live = [ln for ln in lines if ln.strip()]
    shapes = [shape(ln) for ln in live]
    from collections import Counter

    c = Counter(shapes)
    dom = c.most_common(1)[0][1] / len(shapes) if shapes else 0.0
    prose = 0
    for ln in live:
        words = [w for w in ln.replace("#", " ").replace("*", " ").split() if len(w) >= 2 and w.isalpha()]
        if len(words) >= 4:
            prose += 1
    mime = subprocess.run(["file", "-b", "--mime-type", path], capture_output=True, text=True).stdout.strip()
    return {
        "path": path,
        "bytes": len(raw),
        "lines": len(lines),
        "live": len(shapes),
        "kv_frac": round(kv_frac(lines), 3),
        "dom_shape": round(dom, 3),
        "prose_frac": round(prose / len(live), 3) if live else 0.0,
        "tab_frac": round(sum(1 for ln in live if "\t" in ln) / len(live), 3) if live else 0.0,
        "mime": mime,
        "first": (lines[0][:80] if lines else ""),
    }


def main():
    feats = [feature(p) for p in sorted(find_txt())]
    out = ".agents/slop/sloptxt/features.tsv"
    cols = list(feats[0].keys())
    with open(out, "w") as fh:
        fh.write("\t".join(cols) + "\n")
        for r in feats:
            fh.write("\t".join(str(r[c]).replace("\t", " ") for c in cols) + "\n")
    json.dump(feats, open(".agents/slop/sloptxt/features.json", "w"), indent=1)
    print(f"{len(feats)} owned .txt files -> {out}", file=sys.stderr)
    # denominator split by top-level dir
    from collections import Counter

    top = Counter(r["path"].split(os.sep)[0] for r in feats)
    for k, v in top.most_common():
        print(f"  {v:5d}  {k}", file=sys.stderr)


main()
