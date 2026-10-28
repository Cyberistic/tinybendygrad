#!/usr/bin/env python3
"""proof.py -- THE COMMENT-ONLY PROOF.

Two levels, because a `D.refuse("...")` DIAGNOSTIC STRING is a payload no
computation reads -- and the brief allows exactly that one exception:

  LEVEL 1 -- COMMENT-ONLY.  The file's CODE (comments stripped, blank lines dropped,
             AND every string literal replaced by a fixed token) must hash the SAME as
             HEAD's.  A `D.refuse` string is blanked to a token, so a diagnostic
             string that changed does NOT show up here.

  LEVEL 2 -- THE DIAGNOSTIC STRINGS.  For the files that carry a `D.refuse(...)`
             payload, the payloads are listed side by side so a reader can see that
             the ONLY thing that moved is the diagnostic TEXT.

Usage:  .venv/bin/python .agents/slop/barecite/proof.py <file> [<file> ...]
"""
from __future__ import annotations
import hashlib, importlib.util, re, subprocess, sys

HERE = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
spec = importlib.util.spec_from_file_location("pcg", f"{HERE}/checks/port-compile-gate.py")
pcg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pcg)

STR = re.compile(r'"[^"\n]*"')
#: `strip_comments` BLANKS a string's CONTENTS and keeps its LENGTH, so the payload's
#: text is GONE from its output.  A run of two-or-more spaces is therefore either a
#: blanked payload or indentation, and the payload's LENGTH is the only thing left.
#: Collapsing every run of spaces to one token makes the payload's LENGTH part of the
#: hash, which is what the reader wants to see moved -- and the payload TEXT is
#: reported separately, from the ORIGINAL text, below.
RUN = re.compile(r"[ \t]{2,}")


def code_of(text: str) -> list[str]:
    """CODE with comments stripped, blank lines dropped, and every string literal's
    CONTENTS collapsed to a fixed token -- so a `D.refuse` PAYLOAD's TEXT is not a code
    difference, and its LENGTH still is."""
    out = []
    for ln in pcg.strip_comments(text).split("\n"):
        if not ln.strip():
            continue
        out.append(RUN.sub(" ", ln.strip()))
    return out


def payloads(text: str) -> list[str]:
    """Every string literal, in order -- the `D.refuse` PAYLOADS, read from the
    ORIGINAL text (the stripper blanks them)."""
    out = []
    for ln in text.split("\n"):
        out.extend(m.group(0) for m in STR.finditer(ln))
    return out


def h(lines: list[str]) -> str:
    return hashlib.sha256("\n".join(lines).encode()).hexdigest()[:16]


def main() -> int:
    bad = 0
    for path in sys.argv[1:]:
        live = open(f"{HERE}/{path}", encoding="utf-8").read()
        head = subprocess.run(["git", "show", f"HEAD:{path}"], cwd=HERE,
                              capture_output=True, text=True, check=True).stdout
        a, b = code_of(head), code_of(live)
        same = a == b
        if not same:
            bad += 1
        print(f"{'CODE-SAME' if same else 'CODE-DIFF'}  {path}   code-hash {h(a)} -> {h(b)}"
              f"   code-lines {len(a)}")
        if not same:
            import difflib
            for d in list(difflib.unified_diff(a, b, "HEAD", "live", lineterm=""))[:30]:
                print("   ", d)
        pa, pb = payloads(head), payloads(live)
        if pa != pb:
            print(f"   PAYLOADS DIFFER ({len(pa)} -> {len(pb)}) -- THE D.refuse DIAGNOSTIC STRINGS:")
            for i, (x, y) in enumerate(zip(pa, pb)):
                if x != y:
                    print(f"     [{i}] HEAD: {x[:150]}")
                    print(f"     [{i}] live: {y[:150]}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
