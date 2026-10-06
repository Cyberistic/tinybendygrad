#!/usr/bin/env python3
"""THE RE-ADJUDICATION, AND IT FIXES THE INSTRUMENT'S OWN FALSE POSITIVE IN THE RIGHT PLACE.

`checks/citation-gate.py` picks **the longest backtick span on the citation's line** and compares
only that one. But a citation line often carries several spans, and a citation is about ONE of
them. `_render_fn` -- llvmir.py:156-160 ... and `_render_footer`. The longest is `_render_footer`,
which is not at 156, so the gate reports `STALE-LINE` on a citation that is exactly right.

So: **every span on the citation's line is a candidate claim**, and each is adjudicated against the
BLOB the comment was written against and then against HEAD. A row is only `STALE-LINE` if NO span
on its line lands where the citation says.

    .venv/bin/python .agents/slop/stale269/readjudicate.py rows.tsv CLASS [SUBSTR] > adjudicated.out

Per row it prints the chosen span, what the blob's cited line says, and what HEAD's line says, and
the verdict:

| verdict | meaning |
|---|---|
| `HOLDS`          | a span on this line is on the cited line, in the blob AND at HEAD. The gate mis-picked the span. |
| `STALE-LINE`     | no span is there; the whole-text match names where it went. RESTORE. |
| `STALE-FILE`     | no span is in the cited file at all, but one is in another. RESTORE the file too. |
| `STALE-BLOB`     | a span IS at the cited line in the blob but not at HEAD. The line MOVED. RESTORE. |
| `STALE-UNSHOWN`  | a span is at the cited line in the blob, the cited line still exists, and no span is on it now. NAME IT. |
| `NO-SPAN`        | no span on the line sits in the blob's cited line. Content only. |

**`HOLDS` IS A FINDING AGAINST THE INSTRUMENT, NOT A FINDING AGAINST THE COMMENT**, and that
distinction is the whole reason this file exists: retyping a number on a row the gate mis-picked
would have put 26 wrong numbers into the port, each looking done.
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
HERE = os.path.join(ROOT, ".agents/slop/stale269")
QUOTE = re.compile(r"`([^`\n]{4,400})`")   # LOWER bound than the gate's 8: a short span is still a claim
CITE = re.compile(r"(?<![\w./-])((?:[\w.-]+/)*[\w.-]+\.py):(\d+)(?:-(\d+))?")
EXCL = ("tinybendygrad/uop/ops.bend", "tinybendygrad/uop/fold.bend",
        "tinybendygrad/helpers.bend", "tinybendygrad/graphcmp.bend")


def show(commit: str, path: str) -> str | None:
    r = subprocess.run(["git", "show", f"{commit}:{path}"], cwd=ROOT, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def phist(port: str, line: int) -> list[str]:
    r = subprocess.run(["git", "log", "-L", f"{line},{line}:{port}", "--format=%h"],
                       cwd=ROOT, capture_output=True, text=True)
    return [c for c in r.stdout.split() if re.fullmatch(r"[0-9a-f]{7,}", c)]


def hits(b: str, q: str) -> list[int]:
    return sorted({b[: m.start()].count("\n") + 1 for m in re.finditer(re.escape(q), b)})


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def lt(b: str, n: int) -> str:
    ls = b.splitlines()
    return ls[n - 1] if 0 < n <= len(ls) else ""


def main(argv: list[str]) -> int:
    rows = open(argv[1], encoding="utf-8").read().splitlines()[1:]
    want, filt = argv[2], (argv[3] if len(argv) > 3 else "")
    idx = G.python_files()
    out, tally = [], {}
    for f in rows:
        cls, port, pl, name, cl, near, dist, occ, other, quote = f.split("\t")
        if cls != want or (filt and filt not in port):
            continue
        src = open(os.path.join(ROOT, port), encoding="utf-8").read().splitlines()
        line = src[int(pl) - 1]
        m = next((c for c in CITE.finditer(line) if c.group(1) == name and c.group(2) == cl), None)
        if m is None:
            continue
        lo, hi = int(cl), int(m.group(3)) if m.group(3) else int(cl)
        spans = [s for s in QUOTE.findall(line) if len(s) >= 4]
        tgt = G.resolve(name, port, idx)
        rp = os.path.relpath(tgt, ROOT) if tgt else name
        head = show("HEAD", rp) or ""
        blob = hb = None
        for c in phist(port, int(pl)):
            b = show(c, rp)
            if b is not None:
                blob, hb = c, b
                break
        verdict, span, new = "NO-BLOB", quote, ""
        if tgt is None:
            verdict = "STALE-FILE"
        elif hb is None:
            verdict = "NO-BLOB"
        else:
            bl = hb.splitlines()
            hl = head.splitlines()
            # THE WINDOW IS THE CITED SPAN AND NOTHING ELSE. A `name.py:N` citation names ONE
            # line, so a span one line away is a stale number, not a hold; and a `name.py:A-B`
            # citation names the range, so a span inside it holds. Widening this window by one
            # line in either direction is how an off-by-one becomes a `HOLDS` verdict that looks
            # finished -- it is the SAME failure as taking the nearest occurrence.
            win = range(max(1, lo), min(len(bl), hi) + 1)
            winh = range(max(1, lo), min(len(hl), hi) + 1)
            inblob = [s for s in spans if any(s in bl[n - 1] for n in win)]
            inhead = [s for s in spans if any(s in hl[n - 1] for n in winh)]
            both = [s for s in inblob if s in inhead]
            if both:
                verdict, span = "HOLDS", max(both, key=len)
            elif inhead:
                verdict, span = "HOLDS", max(inhead, key=len)   # the range moved onto the span
            elif inblob:
                # MOVED: the span's line in the blob, carried to HEAD by its whole text.
                s = max(inblob, key=len)
                bq = hits(hb, s)
                pick = lo if lo in bq else (bq[0] if bq else None)
                if pick is None:
                    verdict, span = "NO-SPAN", s
                else:
                    key = norm(lt(hb, pick))
                    ex = [n for n in hits(head, s) if norm(lt(head, n)) == key]
                    if ex:
                        verdict, span, new = "STALE-LINE", s, str(ex[0])
                    else:
                        sc = sorted(((difflib.SequenceMatcher(None, key, norm(lt(head, n))).ratio(), n)
                                     for n in hits(head, s)), reverse=True)
                        if sc and sc[0][0] >= 0.85:
                            verdict, span, new = "STALE-LINE", s, str(sc[0][1])
                        else:
                            verdict, span = "STALE-UNSHOWN", s
            else:
                span = max(spans, key=len) if spans else quote
                cands = sorted({head[: x.start()].count("\n") + 1
                                for x in re.finditer(re.escape(span), head)}) if span else []
                if not cands:
                    verdict, span = "NO-SPAN", span
                else:
                    # NO SPAN IS AT THE CITED LINE IN THE BLOB: a RANGE, or a number that was
                    # never right. If a candidate is INSIDE the cited range, the citation HOLDS.
                    inside = [n for n in cands if lo <= n <= hi]
                    if inside:
                        verdict, span, new = "HOLDS", span, str(inside[0])
                    else:
                        sc = sorted(((difflib.SequenceMatcher(None, norm(lt(hb, n)), norm(lt(head, c))).ratio(), c)
                                     for n in hits(hb, span) for c in cands), reverse=True)
                        verdict, span, new = "STALE-LINE", span, str(sc[0][1]) if sc else ""
        tally[verdict] = tally.get(verdict, 0) + 1
        fenced = port.startswith(EXCL)
        out.append((verdict, cls, port, pl, rp, cl, new, span, quote, fenced,
                    f"{rp}:{cl} -> {new or '?'}  span `{span}`", src[int(pl) - 1].strip(),
                    lt(head, int(new)) if new.isdigit() else ""))
    with open(os.path.join(HERE, f"adjudicated-{want}.tsv"), "w", encoding="utf-8") as fh:
        fh.write("verdict\tcensus\tport\tpl\trp\tcl\tnew\tspan\tgatespan\tfenced\tcoord\tclaim\tnewline\n")
        for o in out:
            fh.write("\t".join(str(x).replace("\t", " ") for x in o) + "\n")
    for v, n in sorted(tally.items()):
        print(f"  {v:14} {n:4d}", file=sys.stderr)
    print(f"  {len(out)} rows", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))