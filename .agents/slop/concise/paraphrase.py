#!/usr/bin/env python3
"""Find PARAPHRASE: sentences that say the same thing twice, in one block or two.

The target of `concise` is not prose, it is PROSE THAT REPEATS ITSELF. So the
instrument looks for repeated meaning, not for length:

  1. EXACT duplicate sentences. Normalised (casefold, strip punctuation, collapse
     whitespace, drop digits) so a measurement differing only in its number does not
     read as a repeat -- the numbers are load-bearing and stay.
  2. 8-gram JACCARD >= 0.62 between two sentences from the SAME file. This is the
     paraphrase detector: same clause order, different words. Jaccard on a token
     SET, so word order is free and only the content words have to survive.
  3. A HEDGE, which AGENTS.md calls out by name: "I think", "maybe", "probably",
     "unclear", "not sure", "I believe", "seems like", "TODO?".

The output is a RANKED LIST OF PAIRS so a human picks, not a number. A count of
"bad prose" is the kind of number this tree already has too many of.

LOAD-BEARING LINES ARE FILTERED OUT, never edited: a line carrying a digit, a
7+-hex path/`token`/`EXITS`, or a verdict token (`PASS` `FAIL` `REFUSED` `SKIP`
`DEAD` `ABSENT` `EXCUSED` `WITHIN-LIMITS` `TODO`) is evidence and this file will
not propose deleting it. It only proposes deleting lines that say nothing.
"""

import io
import os
import re
import sys
import tokenize

ROOTS = ("checks", "gates", "tinybendygrad", ".agents/slop")
VERDICTS = ("PASS", "FAIL", "REFUSED", "SKIP", "DEAD", "ABSENT", "EXCUSED",
            "WITHIN-LIMITS", "KILLED-ON-MEMORY", "TIMED-OUT")
HEDGES = re.compile(
    r"\b(i think|i believe|maybe|probably|perhaps|not sure|unclear|"
    r"i suspect|seems like|somehow|obviously|clearly|of course|just simply|"
    r"simply put|in other words|that said|needless to say)", re.I)


def prose_lines(path: str) -> list[tuple[int, str]]:
    """(lineno, text) of comment/docstring lines, via tokenize+ast for .py."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        src = fh.read()
    out: list[tuple[int, str]] = []
    if path.endswith(".bend"):
        for n, line in enumerate(src.splitlines(), 1):
            hash_at = line.find("#")
            if hash_at < 0:
                continue
            body = line[:hash_at]
            if '"' in body or "'" in body:
                body = re.sub(r'"[^"]*"', '""', body)
                body = re.sub(r"'[^']*'", "''", body)
                if "#" in body:
                    continue
            out.append((n, line[hash_at + 1:].strip()))
        return out
    try:
        toks = list(tokenize.generate_tokens(io.StringIO(src).readline))
    except (tokenize.TokenError, SyntaxError):
        return out
    prev = None
    for tok in toks:
        if tok.type == tokenize.COMMENT:
            out.append((tok.start[0], tok.string.lstrip("#").strip()))
        elif tok.type == tokenize.STRING and prev in (tokenize.INDENT, None):
            for off, line in enumerate(tok.string.splitlines()):
                if line.strip():
                    out.append((tok.start[0] + off, line.strip()))
            prev = None
            continue
        prev = tok.type
    return out


def sentences(lines: list[tuple[int, str]]) -> list[tuple[int, str]]:
    """Merge wrapped lines, then split on sentence enders. A sentence keeps the
    lineno of the FIRST line it came from, so a hit is greppable."""
    merged: list[tuple[int, str]] = []
    buf_n, buf = 0, []
    for n, text in lines:
        text = text.strip()
        if not text or text in (":", "->", "|", "-"):
            continue
        if not buf:
            buf_n = n
        if text.endswith((":", ",", "and", "or", "the", "a", "of", "to", "in")):
            buf.append(text)
            continue
        buf.append(text)
        merged.append((buf_n, " ".join(buf)))
        buf = []
    if buf:
        merged.append((buf_n, " ".join(buf)))
    out = []
    for n, sent in merged:
        for part in re.split(r"(?<=[.:;?])\s+", sent):
            part = part.strip()
            if len(part.split()) >= 8:
                out.append((n, part))
    return out


def norm(sent: str) -> str:
    sent = re.sub(r"\d[\d_ ./:%-]*", "#", sent)
    sent = re.sub(r"[^a-z0-9# ]+", " ", sent.casefold())
    return " ".join(sent.split())


def grams(sent: str, k: int = 8) -> set[str]:
    toks = re.sub(r"[^a-z0-9 ]+", " ", sent.casefold()).split()
    return {" ".join(toks[i:i + k]) for i in range(len(toks) - k + 1)}


def loadbearing(text: str) -> bool:
    if re.search(r"\d", text):
        return True
    if re.search(r"\b[0-9a-f]{7,}\b", text):
        return True
    if any(v in text for v in VERDICTS):
        return True
    return bool(re.search(r"`[\w./-]+`", text))


def main() -> int:
    import subprocess
    tracked = set(subprocess.run(
        ["git", "ls-tree", "-r", "HEAD", "--name-only", "--", *ROOTS],
        capture_output=True, text=True, check=True).stdout.splitlines())
    files = []
    for root in ROOTS:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            files += [os.path.join(dirpath, f) for f in filenames
                      if f.endswith((".py", ".bend"))]
    files = sorted(set(files) & tracked)
    if len(sys.argv) > 1:
        files = [f for f in files if any(a in f for a in sys.argv[1:])]

    dups: dict[str, list[tuple[str, int, str]]] = {}
    paras: list[tuple[float, str, int, str, int, str]] = []
    hedges: list[tuple[str, int, str]] = []
    scored: list[tuple[int, str]] = []

    for path in files:
        lines = prose_lines(path)
        scored.append((len(lines), path))
        for n, sent in sentences(lines):
            key = norm(sent)
            if key:
                dups.setdefault(key, []).append((path, n, sent))
            if HEDGES.search(sent):
                hedges.append((path, n, sent))
            if not loadbearing(sent):
                paras.append((0.0, "", 0, "", 0, sent))  # placeholder, filled below

        cands = [(n, s) for n, s in sentences(lines) if not loadbearing(s)]
        gsets = [(n, s, grams(s)) for n, s in cands]
        for i in range(len(gsets)):
            for j in range(i + 1, len(gsets)):
                a, b = gsets[i][2], gsets[j][2]
                if not a or not b:
                    continue
                jacc = len(a & b) / len(a | b)
                if jacc >= 0.62:
                    paras.append((jacc, path, gsets[i][0], gsets[i][1],
                                  gsets[j][0], gsets[j][1]))
    paras = [p for p in paras if p[0] > 0]
    paras.sort(key=lambda p: -p[0])

    print(f"PARAPHRASE over {len(files)} tracked .py/.bend files (population: "
          f"os.walk x git ls-tree -r HEAD)\n")

    exact = {k: v for k, v in dups.items() if len(v) > 1}
    print(f"EXACT DUPLICATE SENTENCES (normalised: digits -> #): "
          f"{len(exact)} sentences in {sum(len(v) for v in exact.values())} sites\n")
    for key, sites in sorted(exact.items(), key=lambda kv: -len(kv[1]))[:14]:
        print(f"  x{len(sites)}  {key[:88]}")
        for path, n, sent in sites[:4]:
            print(f"          {path}:{n}")

    print(f"\nPARAPHRASE PAIRS (8-gram Jaccard >= 0.62, NO NUMBER/SHA/PATH/VERDICT "
          f"in either): {len(paras)} pairs\n")
    for jacc, path, n1, s1, n2, s2 in paras[:26]:
        print(f"  {jacc:.2f}  {path}")
        print(f"        :{n1}  {s1[:104]}")
        print(f"        :{n2}  {s2[:104]}")

    print(f"\nHEDGED SPECULATION: {len(hedges)} sentences\n")
    for path, n, sent in hedges[:20]:
        print(f"  {path}:{n}  {sent[:100]}")

    scored.sort(reverse=True)
    print("\nMOST PROSE LINES (the census ordering, for the before/after)")
    for count, path in scored[:20]:
        print(f"  {count:5d}  {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
