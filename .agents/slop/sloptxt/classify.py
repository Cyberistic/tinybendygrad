#!/usr/bin/env python3
"""Classify every owned `.txt` BY CONTENT. No filename is ever consulted for a class.

THE RULE (ordered cascade, first match wins). Every predicate reads BYTES only.

  EMPTY           zero bytes.
  SOURCE          `compile()` accepts it as Python, OR line 1 is a shebang, OR >=2 lines
                  match Bend source form (`def NAME(` / `fn ` / `struct ` set flush left).
  ROWDUMP         a file of homogeneous DATA RECORDS. One of:
                    (a) >=90% of non-blank lines are `key=value` with a symbol-safe key;
                    (b) >=50% of the non-comment lines are CANONICAL ROWS, where a canonical
                        row is a whitespace-separated line whose every token is `digits:payload`
                        (the port's UOp dump form, e.g. `2:i1 5:PARAM 3:f32 ...`).
  TABULAR         >=3 non-blank lines, every one carries the same positive tab count.
  PROSE           >=50% of non-blank lines are NATURAL-LANGUAGE sentences: >=6 whitespace
                  tokens, >=60% of tokens alphabetic, and no `=` (which marks records).
  CAPTURED-STREAM everything else non-empty: verdicts, reports, logs -- tool output.
  UNCLASSIFIED    a classifiable file whose bytes do not decode as UTF-8 (binary in .txt).

`UNCLASSIFIED` and `EMPTY` are NOT `ROWDUMP`: an empty file proves nothing about its shape.
"""
import ast
import json
import os
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
FEAT = os.path.join(ROOT, ".agents/slop/sloptxt/features.json")


def symbol_safe(key):
    return key and all(c.isalnum() or c in "_.:/()[]<>+-*" for c in key) and not key[0].isspace()


def kv_frac(lines):
    live = [l for l in lines if l.strip()]
    if not live:
        return 0.0
    hits = 0
    for l in live:
        i = l.find("=")
        if i > 0 and symbol_safe(l[:i]):
            hits += 1
    return hits / len(live)


def is_canon_row(line):
    toks = line.split()
    if not toks:
        return False
    for t in toks:
        c = t.find(":")
        if c <= 0 or not t[:c].isdigit():
            return False
    return True


def row_frac(lines):
    body = [l for l in lines if l.strip() and not l.lstrip().startswith("#")]
    if not body:
        return 0.0
    return sum(1 for l in body if is_canon_row(l)) / len(body)


def is_prose_line(line):
    toks = line.split()
    if len(toks) < 6 or "=" in line:
        return False
    alpha = sum(1 for t in toks if len(t) >= 2 and t.isalpha())
    return alpha / len(toks) >= 0.6


def prose_frac(lines):
    live = [l for l in lines if l.strip()]
    n = sum(1 for l in live if is_prose_line(l))
    if len(live) < 3 or n < 3:
        return 0.0
    return n / len(live)


def tab_frac(lines):
    live = [l for l in lines if l.strip()]
    if len(live) < 3:
        return False
    counts = {l.count("\t") for l in live}
    return len(counts) == 1 and 0 not in counts


def source_kind(text):
    """SOURCE by positive marker density, NOT by `compile()`: a file of `key=value` data lines
    is valid Python too, and the first version of this rule called 114 row dumps 'source'."""
    lines = text.splitlines()
    if lines and lines[0].startswith("#!"):
        return "SOURCE"
    defs = sum(1 for l in lines if l.startswith(("def ", "class ", "fn ", "struct ", "impl ", "pub ")))
    if defs >= 2:
        return "SOURCE"
    imports = sum(1 for l in lines if l.startswith(("import ", "from ")) and "=" not in l)
    if imports >= 2:
        return "SOURCE"
    return None


def classify(path, text):
    raw = text.encode("utf-8", errors="replace")
    if not raw:
        return "EMPTY", ""
    sk = source_kind(text)
    if sk:
        return sk, "source"
    lines = text.splitlines()
    if kv_frac(lines) >= 0.9:
        return "ROWDUMP", f"kv={kv_frac(lines):.2f}"
    rf = row_frac(lines)
    if rf >= 0.5:
        return "ROWDUMP", f"canon-rows={rf:.2f}"
    if tab_frac(lines):
        return "TABULAR", "tab"
    pf = prose_frac(lines)
    if pf >= 0.5:
        return "PROSE", f"prose={pf:.2f}"
    return "CAPTURED-STREAM", "default"


def main():
    feats = {f["path"]: f for f in json.load(open(FEAT))}
    rows = []
    for path, f in feats.items():
        if not path.startswith(".agents/slop/"):
            continue
        p = os.path.join(ROOT, path)
        raw = open(p, "rb").read()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            rows.append((path, "UNCLASSIFIED", "non-utf8"))
            continue
        cls, rule = classify(path, text)
        rows.append((path, cls, rule))
    with open(".agents/slop/sloptxt/classes.tsv", "w") as fh:
        fh.write("path\tclass\trule\n")
        for r in rows:
            fh.write("\t".join(r) + "\n")
    print(Counter(r[1] for r in rows).most_common(), file=sys.stderr)
    for cls in ("EMPTY", "SOURCE", "TABULAR", "UNCLASSIFIED", "PROSE"):
        print(f"\n=== {cls} ===", file=sys.stderr)
        for r in rows:
            if r[1] == cls:
                print(f"  {r[0]}  [{r[2]}]", file=sys.stderr)


main()
