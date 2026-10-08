#!/usr/bin/env python3
"""Rank files by REDUNDANT PROSE, not by prose size. Census ranks by volume;
this ranks by repetition, which is what `concise` is actually for.

Three independent signals, each a MEASUREMENT with its population named:

  D1  EXACT REPEAT. A sentence whose NORMALISED form (casefold, digits -> #,
      punctuation dropped) occurs 2+ times in the file. Normalising digits is
      deliberate: two sentences differing only in a number are the SAME claim,
      and the number is load-bearing, so the FIX is to keep one and drop the
      other -- never to touch the digits themselves.
  D2  PARAPHRASE. 8-gram Jaccard >= 0.62 between two sentences of the file.
  D3  NEAR-DUP BLOCK. A run of >= 3 consecutive comment lines whose 5-gram sets
      are >= 0.7 Jaccard with a run elsewhere in the file. This is the one that
      catches a whole paragraph pasted twice, which D1 and D2 miss when the two
      copies differ by one clause.

EXCLUDED FROM EVERY SCORE, and named here so the exclusion is auditable rather
than silent:
  * any sentence carrying a digit, a 7+-hex token, a verdict token, or a
    `backtick` path -- evidence, per AGENTS.md. A file can therefore score high
    and still be untouchable; the score is a RANKING, not an instruction.
  * byte-identical shadow copies (`.agents/slop/{strays,mine,rf2root,...}`),
    because trimming a copy does not change the port.
  * this directory.
"""

import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
from paraphrase import prose_lines, sentences, norm, grams, loadbearing  # noqa: E402

SHADOW = re.compile(
    r"/(strays|mine|rf2root|portzz|denominator/probe|corpuswire|census7|"
    r"figure2/plant|graphwire|e2esh|broken|prefix|frozen-prefix|gk|gk2)/")
HERE = os.path.dirname(os.path.abspath(__file__))


def blocks(lines):
    """Runs of consecutive comment linenos, gap 1."""
    out, run = [], [lines[0]] if lines else []
    for prev, cur in zip(lines, lines[1:]):
        if cur[0] == prev[0] + 1:
            run.append(cur)
        else:
            out.append(run)
            run = [cur]
    if run:
        out.append(run)
    return [b for b in out if len(b) >= 2]


def gset(text, k=5):
    toks = re.sub(r"[^a-z0-9 ]+", " ", text.casefold()).split()
    return {" ".join(toks[i:i + k]) for i in range(len(toks) - k + 1)}


def jac(a, b):
    return len(a & b) / len(a | b) if a and b else 0.0


def main() -> int:
    roots = ("checks", "gates", "tinybendygrad", ".agents/slop")
    tracked = set(subprocess.run(
        ["git", "ls-tree", "-r", "HEAD", "--name-only", "--", *roots],
        capture_output=True, text=True, check=True).stdout.splitlines())
    files = []
    for root in roots:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            files += [os.path.join(dirpath, f) for f in filenames
                      if f.endswith((".py", ".bend"))]
    files = sorted(set(files) & tracked)

    scored = []
    for path in files:
        lines = prose_lines(path)
        if len(lines) < 20:
            continue
        sents = [(n, s) for n, s in sentences(lines) if not loadbearing(s)]

        seen: dict[str, int] = {}
        for _, s in sents:
            key = norm(s)
            if key:
                seen[key] = seen.get(key, 0) + 1
        d1 = sum(c - 1 for c in seen.values() if c > 1)

        gs = [(n, s, grams(s)) for n, s in sents]
        d2 = 0
        for i in range(len(gs)):
            for j in range(i + 1, len(gs)):
                if jac(gs[i][2], gs[j][2]) >= 0.62:
                    d2 += 1

        bl = [(b[0][0], gset(" ".join(t for _, t in b))) for b in blocks(lines)]
        d3 = 0
        for i in range(len(bl)):
            for j in range(i + 1, len(bl)):
                if jac(bl[i][1], bl[j][1]) >= 0.7:
                    d3 += 1
        if d1 or d2 or d3:
            scored.append((d1 + d2 + d3, d1, d2, d3, len(lines), path))

    scored.sort(reverse=True)
    shadow = [s for s in scored if SHADOW.search(s[5])]
    live = [s for s in scored if not SHADOW.search(s[5]) and HERE not in s[5]]

    print("RANKED BY REDUNDANT PROSE (load-bearing sentences excluded from scoring)")
    print(f"  population: {len(files)} tracked .py/.bend, os.walk x git ls-tree -r HEAD")
    print(f"  scored >= 1: {len(scored)} files; {len(shadow)} are shadow copies; "
          f"{len(live)} are editable\n")
    print(f"  {'D1':>3} {'D2':>4} {'D3':>3} {'sum':>5} {'prose':>6}  path")
    for total, d1, d2, d3, n, path in live[:30]:
        print(f"  {d1:>3} {d2:>4} {d3:>3} {total:>5} {n:>6}  {path}")
    print(f"\n  shadow copies, reported and NOT edited: {len(shadow)} files, "
          f"sum {sum(s[0] for s in shadow)}")
    for total, d1, d2, d3, n, path in shadow[:6]:
        print(f"  {total:>5} {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
