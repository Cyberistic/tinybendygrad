#!/usr/bin/env python3
"""THE PLAN. One row per RESTORE, each with the line it names and the decision that chose it, and
the plan is only written when every row carries a `why`.

    .venv/bin/python .agents/slop/stale269/plan.py rows.tsv

**THE RESTORE IS NOT "PUT THE CURRENT NUMBER BACK".** For `STALE-LINE` the number is taken from
the blob the comment was written against (`git log -L` on the port line), by matching the
historical line's WHOLE TEXT at HEAD -- not the nearest occurrence, which is the pin that read
`Allocator` inside `BumpAllocator`. `WRONG-FILE` and `NO-FILE` are resolved by CONTENT across the
whole tree and are restored to the file that actually carries the text, with the path written out
in full so the next reader is not left to re-derive the mirror. `PAST-EOF` is the same question.

ROWS THIS FILE REFUSES TO PLAN, and it says so rather than guessing:
  * a `STALE-LINE` whose text is INSIDE the cited RANGE -- the gate reads only the range start
  * a row whose port file is fenced off (NOT this unit's)
  * a row whose restore would need a number with nothing behind it

Every planned row is emitted with `why` naming the evidence, and `line` PASTED, so the plan is
checkable by reading rather than by trusting.
"""
import csv
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
EXCL = ("tinybendygrad/uop/ops.bend", "tinybendygrad/uop/fold.bend",
        "tinybendygrad/helpers.bend", "tinybendygrad/graphcmp.bend")
CITE = re.compile(r"(?<![\w./-])((?:[\w.-]+/)*[\w.-]+\.py):(\d+)(?:-(\d+))?")
# Files the whole-tree content search may land in, widest first: the port's subject, then the
# trees a citation may legitimately name, then the harness.
TREES = ("tinygrad", "examples", "extra", "test")


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


def all_py() -> list[str]:
    out = []
    for t in TREES:
        for dp, dn, fn in os.walk(os.path.join(ROOT, t)):
            dn[:] = [d for d in dn if d != "__pycache__"]
            out += [os.path.relpath(os.path.join(dp, f), ROOT) for f in fn if f.endswith(".py")]
    return sorted(out)


def main(argv: list[str]) -> int:
    rows = open(argv[1], encoding="utf-8").read().splitlines()[1:]
    idx = G.python_files()
    paths = all_py()
    heads: dict[str, str] = {}

    def head_of(p: str) -> str:
        if p not in heads:
            heads[p] = open(os.path.join(ROOT, p), encoding="utf-8", errors="replace").read()
        return heads[p]

    plan: list[dict] = []
    skipped: dict[str, list[str]] = {}
    for f in rows:
        cls, port, pl, name, cl, near, dist, occ, other, quote = f.split("\t")
        if cls not in ("STALE-LINE", "WRONG-FILE", "NO-FILE", "PAST-EOF"):
            continue
        why_skip = None
        if port.startswith(EXCL):
            why_skip = "FENCED"
        else:
            src = open(os.path.join(ROOT, port), encoding="utf-8").read().splitlines()
            line = src[int(pl) - 1]
            m = next((c for c in CITE.finditer(line) if c.group(1) == name and c.group(2) == cl), None)
            tgt = G.resolve(name, port, idx)
            if m is not None and m.group(3) is not None and tgt is not None:
                lo, hi = int(cl), int(m.group(3))
                inr = [n for n in hits(head_of(os.path.relpath(tgt, ROOT)), quote) if lo <= n <= hi]
                if inr:
                    why_skip = f"NOT-BROKEN range {name}:{lo}-{hi} carries the text at {inr}"
        if why_skip:
            skipped.setdefault(why_skip.split()[0], []).append(f"{port}:{pl} {name}:{cl}  {why_skip}")
            continue

        # --- STALE-LINE: the blob, the historical line, then the WHOLE TEXT at HEAD.
        if cls == "STALE-LINE":
            rp = os.path.relpath(G.resolve(name, port, idx), ROOT)
            head = head_of(rp)
            blob = hb = None
            for c in port_history(port, int(pl)):
                b = show(c, rp)
                if b is not None:
                    blob, hb = c, b
                    break
            if hb is None:
                skipped.setdefault("NO-BLOB", []).append(f"{port}:{pl} {name}:{cl}")
                continue
            hq = hits(hb, quote)
            if int(cl) in hq:
                verdict, hl = "MOVED", int(cl)
            elif len(hq) == 1:
                verdict, hl = "MISNUMBERED", hq[0]
            else:
                skipped.setdefault("AMBIG", []).append(
                    f"{port}:{pl} {rp}:{cl}  quote in blob {blob} at {hq}; head at {hits(head, quote)}")
                continue
            key = norm(ltext(hb, hl))
            exact = [n for n in hits(head, quote) if norm(ltext(head, n)) == key]
            if exact:
                new, score, why = exact[0], 1.0, f"{verdict}, exact whole-line match of {blob}:{hl}"
            else:
                sc = sorted(((difflib.SequenceMatcher(None, key, norm(ltext(head, n))).ratio(), n)
                             for n in hits(head, quote)), reverse=True)
                score, new = sc[0]
                why = f"{verdict}, whole-line similarity {score:.3f} to {blob}:{hl} -- READ THIS ONE"
                skipped.setdefault("WEAK", []).append(f"{port}:{pl} {rp}:{cl}->{new} {score:.3f}")
                if score < 0.9:
                    continue
            plan.append(dict(cls=cls, port=port, pl=pl, rp=rp, cl=int(cl), new=new,
                             why=why, score=score, quote=quote, line=ltext(head, new).strip()))
            continue

        # --- WRONG-FILE / NO-FILE / PAST-EOF: resolve by CONTENT across the whole tree.
        cand = []
        for p in paths:
            ls = hits(head_of(p), quote)
            if ls:
                cand.append((p, ls))
        if not cand:
            skipped.setdefault("UNRESOLVED", []).append(f"{port}:{pl} {name}:{cl} `{quote}`")
            continue
        plan.append(dict(cls=cls, port=port, pl=pl, rp="", cl=int(cl), new=0,
                         why=f"{len(cand)} file(s) carry the text: "
                             + "; ".join(f"{p}:{ls[:4]}" for p, ls in cand[:4]),
                         score=0.0, quote=quote, line=""))
    with open(os.path.join(HERE, "restore-plan.tsv"), "w", encoding="utf-8") as fh:
        fh.write("cls\tport\tpl\trp\tcl\tnew\tscore\twhy\tquote\tline\n")
        for p in plan:
            fh.write("\t".join(str(p[k]).replace("\t", " ") for k in
                                ("cls", "port", "pl", "rp", "cl", "new", "score", "why", "quote", "line")) + "\n")
    print(f"  PLANNED {len(plan)}")
    for k, v in sorted(skipped.items()):
        print(f"  SKIPPED {len(v):4d}  {k}")
    with open(os.path.join(HERE, "skipped.tsv"), "w", encoding="utf-8") as fh:
        fh.write("reason\trow\n")
        for k, v in sorted(skipped.items()):
            for x in v:
                fh.write(f"{k}\t{x}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))