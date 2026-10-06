#!/usr/bin/env python3
"""THE PRE-WRITE AUDIT, AND IT AUDITS **MY OWN** RESTORES WITH THE CLASS THE BRIEF NAMED.

    .venv/bin/python .agents/slop/stale269/audit.py rows.tsv [--dry]

A restore that puts a number on a line that does not say the thing is the WORST outcome available,
because it looks done. So every planned restore is checked four ways before anything is written, and
a failure in any of them is a REFUSAL:

1. **THE PREFIX CLASS.** The brief's `Allocator`-inside-`BumpAllocator`, and `abi4_gate.py`'s
   `S.Dt`/`S.DtX`. If the matched occurrence on the target line is followed by a word character, the
   quote is a PREFIX of a longer token and the row is flagged. Counted either way.
2. **THE TARGET SAYS IT.** At least one backtick span of the CLAIM LINE must be present on the
   target line. Checking only the gate's span is what let `reduce.py:44/:71` become `:71/:71`.
3. **THE CLAIM'S OWN WORDS.** At least one content word of the claim must be present on the target
   line -- a restore whose target has no word in common with the claim is a coordinate with no
   claim behind it.
4. **NO COLLAPSED LIST.** A claim line naming several lines must not be edited into two identical
   numbers, which reads as checked and says nothing.
"""
import csv
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
HERE = os.path.join(ROOT, ".agents/slop/stale269")
import importlib.util  # noqa: E402

_s = importlib.util.spec_from_file_location("citation_gate", os.path.join(ROOT, "checks/citation-gate.py"))
G = importlib.util.module_from_spec(_s)
_s.loader.exec_module(G)
CITE = re.compile(r"(?<![\w./-])((?:[\w.-]+/)*[\w.-]+\.py):(\d+)(?:-(\d+))?")
SIBLING = re.compile(r"(?:,|/|;)\s*:(\d+)")
STOP = set("the a an of and or is are in to for that it its with on at be as by not from this these "
           "those one two three four five six half only both where which while so if then else".split())


def main(argv: list[str]) -> int:
    rows = open(argv[1], encoding="utf-8").read().splitlines()[1:]
    fin = {(r["port"], r["pl"]): r for r in csv.DictReader(open(os.path.join(HERE, "FINAL.tsv")), delimiter="\t")}
    res = {r["key"]: r for r in csv.DictReader(open(os.path.join(HERE, "resolutions.tsv")), delimiter="\t")}
    npfx = nref = nok = 0
    for f in rows:
        cls, port, pl, name, cl, near, dist, occ, other, quote = f.split("\t")
        if cls not in ("STALE-LINE", "WRONG-FILE", "NO-FILE", "PAST-EOF"):
            continue
        key = (port, pl)
        row = fin.get(key)
        if row is None or row["verdict"] == "FENCED":
            continue
        h = res.get(f"{port}:{pl}")
        if h is not None:
            if h["verdict"] != "RESTORE":
                continue
            tgt, new = h["file"].strip(), h["line"].strip()
            span = None
        else:
            if row["verdict"] != "RESTORE-LINE":
                continue
            tgt, new, span = row["rp"], row["new"], (row["span"] or quote)
        if not new.isdigit() or not tgt:
            continue
        body = open(os.path.join(ROOT, tgt), encoding="utf-8", errors="replace").read().splitlines()
        n = int(new)
        if n > len(body):
            nref += 1
            print(f"PAST-EOF   {port}:{pl} {tgt}:{n} of {len(body)}")
            continue
        target = body[n - 1]
        claim = open(os.path.join(ROOT, port), encoding="utf-8").read().splitlines()[int(pl) - 1]
        # 1. THE PREFIX CLASS
        q = span or quote
        if q in target:
            i = target.index(q) + len(q)
            if i < len(target) and re.match(r"\w", target[i]):
                npfx += 1
                print(f"PREFIX     {port}:{pl} -> {tgt}:{n}  `{q}` runs into {target[i:i+14]!r}")
        # 2. THE TARGET SAYS IT
        # THE GATE'S OWN `QUOTE`, IMPORTED, not a second one. Lowering its bound from 8 to 4 admits the
        # JUNK BETWEEN TWO SPANS -- on `# \`ilt\` of \`nif\`, \`END\` and \`BACKEDGE\`` a {4,400} bound yields
        # [' of ', ' and '] and misses `BACKEDGE` entirely, because the scan resumes past it. A second
        # tokenizer here would have agreed with itself and been wrong about the claim.
        spans = G.QUOTE.findall(claim)
        if span is None and spans and not any(s in target for s in spans):
            nref += 1
            print(f"NO-SPAN    {port}:{pl} -> {tgt}:{n}  no claim span on the line: {target.strip()[:70]}")
            continue
        # 3. THE CLAIM'S OWN WORDS. A 3-CHAR floor: a citation's subject is often a short identifier
        # (`ler`, `src`, `ops`) and a 4-CHAR floor flags correct restores.
        words = [w for w in re.findall(r"[A-Za-z_][A-Za-z0-9_]{2,}", claim) if w.lower() not in STOP]
        if words and not any(w in target for w in words):
            nref += 1
            print(f"NO-WORD    {port}:{pl} -> {tgt}:{n}  {target.strip()[:70]}")
            continue
        # 4. NO COLLAPSED LIST
        sibs = SIBLING.findall(claim)
        toks = [c for c in CITE.finditer(claim) if c.group(2) == cl]
        if h is None and (len(toks) > 1 or sibs):
            nref += 1
            print(f"MULTI      {port}:{pl} cites {cl} plus {sibs}")
            continue
        nok += 1
    print(f"\n  {nok} restores pass all four checks; {nref} flagged; {npfx} carry a PREFIX anchor",
          file=sys.stderr)
    return 1 if nref else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))