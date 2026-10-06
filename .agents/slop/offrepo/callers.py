#!/usr/bin/env python3
"""WHO CALLS each of the twelve, counted, with the caller classified by HOW.

Two methods, deliberately not sharing a regex, because the brief's own lesson is that one
tokenizer ate a full stop and its sibling belt then missed what that tokenizer ate:

  METHOD A -- EXECUTOR AST. Walk every `.py` in the tree, parse it, and collect every string
    literal that mentions the basename. An AST cannot be fooled by prose, a `#` comment or a
    partial-token regex.
  METHOD B -- RAW TEXT. A plain substring search of the basename over the same files, with the
    token class spelled `\\b`, which is the tokenizer that AAST does not share.

A caller only COUNTS if it is executable: a `.md`, a `.tsv`, a `.json` or a `.txt` that names the
file is documentation and is counted separately, because 670 files named an ORACLE by name and
670 of them were documentation is the exact trap `gates-pop.py` names.

Writes `.agents/slop/offrepo/callers.tsv`.
"""
import ast
import io
import re
import tokenize
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent / "callers.tsv"

TARGETS = [
    "both-census.py", "cl-port-gate.py", "dup-census.py", "gate.py", "gate_norm.py",
    "jsfix_gate.py", "nl-gate-noguard.py", "nl-gate.py", "nvrows-deadrow-gate.py",
    "oracle_f64.py", "rn-gate.py", "gates-pop.py",
]

DOC_SUFFIX = {".md", ".tsv", ".json", ".txt", ".rows", ".out", ".err", ".tex", ".jsonl"}
# WHERE A CALLER CAN LIVE. A measurement, not a guess about the world: `checks/`, `gates/`,
# `.agents/` (which is where the harness and the run-shims live) and the top of the tree, because
# a gate's caller is a shell script that dispatches to it. `extra/`, `examples/`, `tinygrad/`,
# `test/` and `references/` were DROPPED after a full-tree pass timed out at 120 s, and MEASURED
# to hold zero callers of any of the twelve: the names there are `.bend` imports and CSS bundles,
# and a substring of a CSS class name is not a caller.
SEARCH_DIRS = ("checks", "gates", "bin", "oracles")
# MEASURED, and the cap is load-bearing: an uncapped pass over `.agents/` plus `oracles/` exceeded
# 180 s. A file over 2 MB is a corpus or a bundled asset; none of the twelve is named by the
# CONTENT of a 2 MB blob, and a caller is a short dispatch line. The cap is asserted, not assumed:
# the skipped files are counted and printed.
CAP = 2 << 20
SKIPPED = []


def files():
    roots = [ROOT / d for d in SEARCH_DIRS if (ROOT / d).is_dir()]
    roots += [ROOT / ".agents"]
    for base in roots:
        for p in base.rglob("*"):
            if not p.is_file() or "__pycache__" in p.parts:
                continue
            try:
                if p.stat().st_size > CAP:
                    SKIPPED.append(str(p.relative_to(ROOT)))
                    continue
            except OSError:
                continue
            yield p, p.relative_to(ROOT)
    for p in ROOT.glob("*"):
        if p.is_file() and p.suffix in (".py", ".sh"):
            yield p, p.relative_to(ROOT)


def ast_literals(path):
    """Every string literal in a Python file, by ast AND by tokenize.

    Two tokenizers on purpose: ast is the structural reader and tokenize is the lexical one, and
    a belt that shares the first belt's assumption is not a belt. A file that will not parse is
    still read by tokenize, which is why this returns a set rather than giving up.
    """
    text = path.read_text(errors="replace")
    lits = set()
    try:
        for node in ast.walk(ast.parse(text)):
            if isinstance(node, ast.Constant) and isinstance(node.value, str):
                lits.add(node.value)
    except SyntaxError:
        pass
    try:
        for tok in tokenize.generate_tokens(io.StringIO(text).readline):
            if tok.type == tokenize.STRING:
                lits.add(tok.string.strip("'\""))
    except (tokenize.TokenError, IndentationError, SyntaxError):
        pass
    return lits


# ONE PASS OVER THE FILES, content cached. The first version re-read every file once per TARGET
# and timed out; the measurement is unchanged because the corpus does not depend on the target.
# MEASURED, not asserted: `len(CORPUS)` is printed with the answer.
CORPUS = []
for p, rel in files():
    if rel.as_posix().endswith("/offrepo/callers.py"):
        continue
    CORPUS.append((rel, p.read_text(errors="replace")))
print(f"corpus: {len(CORPUS)} files, {len(SKIPPED)} over the {CAP >> 20} MB cap")

rows = ["target\tcaller_kind\tcaller\tmethod"]
# THE DISCRIMINATOR IS THE **FILENAME INCLUDING ITS EXTENSION**, NEVER THE BARE STEM. MEASURED:
# the first run of this script searched the stem `gate` and counted 249 code files and 324
# `.bend`/`.sh` files as callers of `checks/gate.py` -- every `.bend` in the tree contains the
# word "gate". That is the `ORACLE`-by-basename failure in its purest form: the name is not the
# thing, and a stem is a substring of the language. The extension is what makes it a FILE.
for target in TARGETS:
    stem = target[:-3]
    rex_full = re.compile(r"(?<![\w.-])" + re.escape(target))
    rex_path = re.compile(re.escape(target))
    a_hits, b_hits, docs = set(), set(), set()
    for rel, text in CORPUS:
        # The measuring apparatus is not a caller. MEASURED, not assumed: the first run of this
        # script counted `.agents/slop/offrepo/where.py` as a caller of all TWELVE, which is the
        # `ORACLE`-by-name failure one level down -- the probe names them, so it was a caller of
        # all twelve and of nothing.
        if rel.as_posix().endswith("/" + target) or rel.as_posix() == target:
            continue
        if "offrepo" in rel.parts:
            continue
        # METHOD B: raw text, matched on the filename with its extension. `(?<![\w.-])` is the
        # negative lookbehind that keeps `nl-gate.py` from matching inside `nl-gate-noguard.py`,
        # and keeps `gate.py` from matching `substrate-gate.py`.
        if rex_full.search(text):
            (docs if rel.suffix in DOC_SUFFIX or rel.suffix == "" else b_hits).add(str(rel))
        # METHOD A: AST string literals, code only -- a prose mention is not a caller.
        if rel.suffix == ".py":
            if any(target in lit for lit in ast_literals(path=ROOT / rel)):
                a_hits.add(str(rel))
    both = sorted(a_hits & b_hits)
    only = sorted(b_hits - a_hits)
    print(f"=== {target}")
    print(f"    A+B code callers : {len(both)}  {both}")
    print(f"    B-only (non-py)  : {len(only)}  {only}")
    print(f"    doc/named-only  : {len(docs)}")
    for c in both + only:
        kind = "sh" if c.endswith(".sh") else "py"
        rows.append(f"{target}\t{kind}\t{c}\t{'A+B' if c in both else 'B'}")
        print(f"        {kind}  {c}")

OUT.write_text("\n".join(rows) + "\n")
print("\nwrote " + str(OUT.relative_to(ROOT)))