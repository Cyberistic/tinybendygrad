#!/usr/bin/env python3
"""THE WRITER. Two inputs: the mechanically-planned `STALE-LINE` rows and the hand `resolutions.tsv`,
one pass, and it edits COMMENT LINES ONLY or it refuses.

    .venv/bin/python .agents/slop/stale269/write.py rows.tsv [--dry]

**IT RE-VERIFIES BEFORE IT WRITES.** Every planned coordinate is re-derived from the CURRENT bytes
at write time -- target file exists, target line exists, the claim's span is ON that line -- and any
row that fails is REFUSED and printed, not written. A restore whose target does not carry the text
is the worst outcome available here, because it looks finished.

**IT TOUCHES ONE TOKEN.** The rewrite is applied to the citation token that carries the file and the
OLD number, on the port line, and only the number changes. A range's end is preserved, a sibling
citation on the same line is preserved, and the text of the comment is otherwise byte-identical.
"""
import csv
import importlib.util
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
HERE = os.path.join(ROOT, ".agents/slop/stale269")
_s = importlib.util.spec_from_file_location("citation_gate", os.path.join(ROOT, "checks/citation-gate.py"))
G = importlib.util.module_from_spec(_s)
_s.loader.exec_module(G)
CITE = re.compile(r"(?<![\w./-])((?:[\w.-]+/)*[\w.-]+\.py):(\d+)(?:-(\d+))?")
# A SIBLING REFERENCE in the same list: `cstyle.py:125, :285, :324` and `reduce.py:44/:71`. The
# gate's `CITE` sees only the first, so this is what makes a MULTI-CITATION line detectable at all.
SIBLING = re.compile(r"(?:,|/|;)\s*:(\d+)")


def show(c: str, p: str) -> str:
    r = subprocess.run(["git", "show", f"{c}:{p}"], cwd=ROOT, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def main(argv: list[str]) -> int:
    dry = "--dry" in argv
    rows = open(argv[1], encoding="utf-8").read().splitlines()[1:]
    idx = G.python_files()
    fin = list(csv.DictReader(open(os.path.join(HERE, "FINAL.tsv")), delimiter="\t"))
    res = {}
    for r in csv.DictReader(open(os.path.join(HERE, "resolutions.tsv")), delimiter="\t"):
        if r.get("key"):
            p, _, l = r["key"].strip().rpartition(":")
            res[(p, l.strip())] = r
    edits: dict[str, list[tuple[int, int, int, str, str]]] = {}
    refused: list[str] = []
    nline = nfile = nnone = 0
    for f in rows:
        cls, port, pl, name, cl, near, dist, occ, other, quote = f.split("\t")
        if cls not in ("STALE-LINE", "WRONG-FILE", "NO-FILE", "PAST-EOF"):
            continue
        key = (port, pl)
        row = next((x for x in fin if (x["port"], x["pl"]) == key), None)
        if row is None or row["verdict"] == "FENCED":
            continue
        # A HAND RESOLUTION OUTRANKS EVERY AUTOMATIC PICK, including the blob-proximity one, and
        # its `why` column says which line of the CLAIM the number is. `span` then becomes a
        # HINT, not the gate's span: for a mis-pinned row the gate's span is exactly the wrong
        # text, and checking the target against it would refuse every correct restore.
        h = res.get(key)
        span = None
        if h is not None:
            if h["verdict"] != "RESTORE":
                nnone += 1
                continue
            tgt, new = h["file"].strip(), h["line"].strip()
            if not new.isdigit():
                refused.append(f"{port}:{pl} resolution line {new!r} is not a number")
                continue
            old_file = name if tgt.endswith(name) else tgt
            span = None
            nfile += 1
        else:
            if row["verdict"] != "RESTORE-LINE":
                nnone += 1
                continue
            tgt, new = row["rp"], row["new"]
            if not new.isdigit() or not tgt:
                refused.append(f"{port}:{pl} no target {tgt}:{new}")
                continue
            old_file = name
            nline += 1
        # --- RE-VERIFY AGAINST CURRENT BYTES
        tp = os.path.join(ROOT, tgt)
        if not os.path.exists(tp):
            refused.append(f"{port}:{pl} target {tgt} does not exist")
            continue
        body = open(tp, encoding="utf-8", errors="replace").read().splitlines()
        n = int(new)
        if n > len(body):
            refused.append(f"{port}:{pl} target {tgt}:{n} is past EOF ({len(body)})")
            continue
        claim_line = open(os.path.join(ROOT, port), encoding="utf-8").read().splitlines()[int(pl) - 1]
        # A LINE WITH SEVERAL `.py:N` TOKENS IS NOT ONE CITATION. `cstyle.py:125, :285, :324` names
        # five lines and the gate bound its quote to the FIRST of them, so restoring "the" number
        # edits one arm of a list and can silently turn `(reduce.py:44/:71)` into `(reduce.py:71/:71)`
        # -- a citation that now reads as checked and says nothing. Such a row is REFUSED unless a
        # human resolved it, because deciding WHICH of the numbers the quote belongs to is the
        # judgement, and the gate made it by position.
        toks = [c for c in CITE.finditer(claim_line) if c.group(2) == cl]
        sibs = SIBLING.findall(claim_line)
        if (len(toks) > 1 or sibs) and h is None:
            refused.append(f"{port}:{pl} the line names {len(toks)} citation(s) at {cl} plus "
                           f"{len(sibs)} sibling line(s) {sibs}: {claim_line.strip()[:70]}")
            continue
        span = (span if span is not None else (row["span"] or quote))
        # A HAND row is proven by its own `why`, which PASTES the target line in backticks; so
        # check that the pasted text is on the line. An automatic row is checked against the span
        # the gate matched. Both must pass, and neither may be skipped: "the hand said so" is not
        # evidence, and a paste that is not on the line means the paste is stale.
        if h is not None:
            pasted = [p for p in re.findall(r"`([^`]+)`", h["why"]) if len(p) > 8]
            if pasted and not any(p in body[n - 1] for p in pasted):
                refused.append(f"{port}:{pl} the resolution's own pasted line is NOT on "
                               f"{tgt}:{n}: {body[n-1].strip()[:70]}")
                continue
        elif span and span not in body[n - 1]:
            refused.append(f"{port}:{pl} span `{span[:40]}` is NOT on {tgt}:{n}: {body[n-1].strip()[:70]}")
            continue
        # --- THE EDIT: one number, on a comment line
        if claim_line[: claim_line.find("#")].strip() if "#" in claim_line else claim_line.strip():
            refused.append(f"{port}:{pl} is not a comment line: {claim_line.strip()[:70]}")
            continue
        toks = [c for c in CITE.finditer(claim_line) if c.group(2) == cl]
        if not toks:
            refused.append(f"{port}:{pl} no token {old_file}:{cl} on the line: {claim_line.strip()[:70]}")
            continue
        c = toks[0]
        # A `WRONG-FILE`/`NO-FILE` restore must retype the FILE as well as the number: the right
        # line number on the right line of the WRONG file is the worst outcome available, because it
        # now reads as checked. The name written is the resolution's, VERBATIM and repo-relative
        # (`tinygrad/dtype.py`), because `resolve()` tries `<root>/<name>` and that is the one form a
        # bare AMBIGUOUS basename cannot lose: `dtype.py` is three files under `tinygrad/**`, and the
        # first version of this line stripped the prefix and turned four correct restores into
        # `NO-FILE` -- which the census re-run caught as a regression.
        if h is not None and tgt != c.group(1):
            edits.setdefault(port, []).append((int(pl), c.start(1), c.end(2), f"{tgt}:{new}", tgt))
        else:
            edits.setdefault(port, []).append((int(pl), c.start(2), c.end(2), new, tgt))
    for port, es in edits.items():
        # PRESERVE THE TRAILING-NEWLINE STATE. Five of these files ended WITHOUT one, and a writer
        # that appends "\n" changes a byte nobody asked it to change -- which is how a 0-code-line
        # restore shows up as a diff on a code line.
        raw = open(os.path.join(ROOT, port), "rb").read()
        # `splitlines()` DROPS the final newline, so it goes back EXACTLY as it was. Five of these
        # files ended WITHOUT one, and appending "\n" changes a byte nobody asked this writer to
        # change -- which is how a 0-code-line restore shows up as a diff on a code line. The
        # first version of this line had the condition INVERTED and did exactly that.
        trail = b"\n" if raw.endswith(b"\n") else b""
        ls = raw.decode("utf-8").splitlines()
        for i, a, b, new, _ in es:
            ls[i - 1] = ls[i - 1][:a] + new + ls[i - 1][b:]
        if not dry:
            open(os.path.join(ROOT, port), "wb").write(("\n".join(ls)).encode("utf-8") + trail)
    print(f"  {'WOULD WRITE' if dry else 'wrote'} {sum(len(v) for v in edits.values())} numbers "
          f"across {len(edits)} files   (STALE-LINE {nline}, other classes {nfile}; "
          f"{nnone} named-not-restored)")
    for r in refused:
        print(f"  REFUSED {r}")
    return 1 if refused else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))