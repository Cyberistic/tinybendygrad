#!/usr/bin/env python3
"""THE RESTORE, AND THE KEY IS **THE HISTORICAL LINE'S WHOLE TEXT**, NOT THE QUOTE.

    .venv/bin/python .agents/slop/stale269/restore.py rows.tsv CLASS [SUBSTR] [-q]

WHY THE QUOTE IS NOT THE KEY. `checks/citation-gate.py` finds a citation's text as a SUBSTRING and
reports the nearest occurrence. That is the pin that read `Allocator` inside `BumpAllocator`, and
it is wrong here too: `tinybendygrad/device.bend:993` cites `device.py:403` for `` `pm_bufferize`
-- device.py:403-405. THE RULE TABLE.`` `pm_bufferize` occurs EXACTLY ONCE at HEAD -- on
`pm_bufferize:Any = None`, a class-attribute DECLARATION -- while the claim is about the
`PatternMatcher([` rule table, which is a different line entirely. "Unique in HEAD" is not proof of
being the right line; it is only proof of not being ambiguous. **That is the `Allocator` class,
and it is why this file searches for the LINE, not the token.**

THE METHOD, in this order, and each step is content:

1. **THE BLOB.** `git log -L<pl>:<port>` names the commits that wrote the port line carrying the
   citation. The first whose blob contains the cited `.py` is a file the author demonstrably had.
2. **THE HISTORICAL LINE.** The quote's line in that blob. If the cited number is among them, the
   number was right once and this is a `MOVED`. If it is not and there is exactly one, the number
   was wrong at birth (`MISNUMBERED`) and this is the line the author meant. Several ->
   `MISNUMBERED-AMBIG`, printed, NOT guessed.
3. **THE WHOLE TEXT.** The historical line's ENTIRE text, whitespace-normalised. This, not the
   quote, is the search key at HEAD.
4. **THE ADDRESS.** Where that whole text is now. Exact match preferred; if HEAD reformatted it,
   the token-overlap best match is reported with its score and needs a reader.
5. **THE BOUNDARY CHECK**, because `abi4_gate.py`'s trap is real: if the quoted token is followed
   by a word character at the restored line, the match sits inside a LONGER name and the row is
   counted and named, not quietly accepted.

Nothing is written. This file only decides and prints; `apply.py` writes, and it only writes
COMMENT lines.
"""
import difflib
import importlib.util
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
_s = importlib.util.spec_from_file_location("citation_gate", os.path.join(ROOT, "checks/citation-gate.py"))
G = importlib.util.module_from_spec(_s)
_s.loader.exec_module(G)
EXCL = ("tinybendygrad/uop/ops.bend", "tinybendygrad/uop/fold.bend",
        "tinybendygrad/helpers.bend", "tinybendygrad/graphcmp.bend")


def show(commit: str, path: str) -> str | None:
    r = subprocess.run(["git", "show", f"{commit}:{path}"], cwd=ROOT, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def port_history(port: str, line: int) -> list[str]:
    r = subprocess.run(["git", "log", "-L", f"{line},{line}:{port}", "--format=%h"],
                       cwd=ROOT, capture_output=True, text=True)
    return [c for c in r.stdout.split() if re.fullmatch(r"[0-9a-f]{7,}", c)]


def hits(body: str, q: str) -> list[int]:
    return sorted({body[: m.start()].count("\n") + 1 for m in re.finditer(re.escape(q), body)})


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def ltext(body: str, n: int) -> str:
    ls = body.splitlines()
    return ls[n - 1] if 0 < n <= len(ls) else ""


def boundary(body: str, q: str, n: int) -> str:
    """`PREFIX` when the match on line n runs into a word char after it -- the `S.Dt` vs `S.DtX`."""
    ls = body.splitlines()
    ln = ls[n - 1] if 0 < n <= len(ls) else ""
    for m in re.finditer(re.escape(q), ln):
        if m.end() < len(ln) and re.match(r"\w", ln[m.end()]):
            return "PREFIX"
    return "ok"


def main(argv: list[str]) -> int:
    positional = [a for a in argv[1:] if not a.startswith("-")]
    quiet = "-q" in argv
    rows = open(positional[0], encoding="utf-8").read().splitlines()[1:]
    want = positional[1]
    filt = positional[2] if len(positional) > 2 else ""
    idx = G.python_files()
    tally: dict[str, int] = {}
    plan: list[tuple] = []
    for f in rows:
        cls, port, pl, name, cl, near, dist, occ, other, quote = f.split("\t")
        if cls != want or (filt and filt not in port):
            continue
        tgt = G.resolve(name, port, idx)
        if tgt is None:
            continue
        rp = os.path.relpath(tgt, ROOT)
        head = show("HEAD", rp) or ""
        hs = hits(head, quote)
        blob, hb = None, None
        for c in port_history(port, int(pl)):
            b = show(c, rp)
            if b is not None:
                blob, hb = c, b
                break
        if hb is None:
            tally["NO-BLOB"] = tally.get("NO-BLOB", 0) + 1
            continue
        hq = hits(hb, quote)
        if int(cl) in hq:
            verdict, hl = "MOVED", int(cl)
        elif len(hq) == 1:
            verdict, hl = "MISNUMBERED", hq[0]
        else:
            tally["MISNUMBERED-AMBIG"] = tally.get("MISNUMBERED-AMBIG", 0) + 1
            if not quiet:
                print(f"\n===== {port}:{pl}  MISNUMBERED-AMBIG  {rp}:{cl}  quote in blob at {hq}")
                src = open(os.path.join(ROOT, port), encoding="utf-8").read().splitlines()
                for i in range(max(0, int(pl) - 1), min(len(src), int(pl) + 2)):
                    print(f"  CLAIM {port}:{i+1}  {src[i].strip()[:170]}")
                for n in hq:
                    print(f"  blob {rp}@{blob}:{n}  {ltext(hb, n).strip()[:170]}")
                for n in hs:
                    print(f"  head {rp}:{n}  {ltext(head, n).strip()[:170]}")
            continue
        key = norm(ltext(hb, hl))
        exact = [n for n in hs if norm(ltext(head, n)) == key]
        if exact:
            new, score = exact[0], 1.0
        else:
            scored = sorted(((difflib.SequenceMatcher(None, key, norm(ltext(head, n))).ratio(), n)
                             for n in hs), reverse=True)
            score, new = scored[0]
        tally[verdict] = tally.get(verdict, 0) + 1
        plan.append((cls, port, pl, rp, cl, new, blob, hl, f"{score:.3f}", verdict,
                     boundary(head, quote, new), quote, ltext(head, new).strip()))
    if not quiet:
        for p in plan:
            cls, port, pl, rp, cl, new, blob, hl, score, verdict, bnd, quote, line = p
            print(f"\n  {port}:{pl}  {rp}:{cl} -> {new}   {verdict} blob {blob}:{hl} score {score} bnd {bnd}")
            print(f"  CLAIM  {open(os.path.join(ROOT, port), encoding='utf-8').read().splitlines()[int(pl)-1].strip()[:170]}")
            print(f"  QUOTE  `{quote}`")
            print(f"  LINE   {rp}:{new}  {line[:170]}")
    with open(os.path.join(ROOT, f".agents/slop/stale269/plan-{want}.tsv"), "w", encoding="utf-8") as fh:
        fh.write("class\tport\tpl\trp\tcl\tnew\tblob\thist\tscore\tverdict\tbnd\tquote\tnewline\n")
        for p in plan:
            fh.write("\t".join(str(x) for x in p) + "\n")
    print("\nTALLY " + "  ".join(f"{k}={v}" for k, v in sorted(tally.items())), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))