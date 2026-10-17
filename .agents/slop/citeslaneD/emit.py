#!/usr/bin/env python3
"""Emit `pricing.rows` from `detail.rows` plus a HAND LABEL FILE, so every REAL/FALSE in the
report has a witness row and can be re-checked.  (The census docstring records the same
defect in its own predecessor: labels that live in REPORT prose are a number with no witness.)

usage: emit.py
"""
import re
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent

# ---- HAND LABELS.  `prior` = the label .agents/slop/citesbacklog/REPORT.md sec 4d gave,
# recovered from its prose (its sample rows carry no label column).  `mine` = labelled here.
LABELS: dict[str, tuple[str, str]] = {
    # --- the prior unit's 6 REALs, of which 4 reproduce at this HEAD
    ".agents/TODO.md:1521":                    ("REAL", "prior"),
    ".agents/slop/guardfix/REPORT.md:14":       ("REAL", "prior"),
    ".agents/slop/brief-port.md:32":            ("REAL", "prior"),
    ".agents/slop/agend2/REPLACEMENTS.md:134":  ("REAL", "prior"),
    ".agents/slop/agend2/REPORT.md:49":         ("REAL", "prior"),
    ".agents/slop/gatesweep/REPORT.md:12":      ("REAL", "prior"),
    # --- the prior unit's 4 FALSE_POSITIVEs
    ".agents/slop/notes/bend2-constraints.md:9029": ("FALSE_POSITIVE", "prior"),
    ".agents/slop/quiescefix/REPORT.md:22":          ("FALSE_POSITIVE", "prior"),
    ".agents/slop/readback/REPORT.md:65":            ("FALSE_POSITIVE", "prior"),
    ".agents/slop/residual/REPORT.md:128":           ("FALSE_POSITIVE", "prior"),
    # --- labelled here, rows the prior unit did not sample
    ".agents/TOOLS.md:392":                      ("REAL", "mine: the cell carries a predicate"),
    ".agents/slop/agend2/REPORT.md:102":         ("REAL", "mine: same 765-vs-936 row, one line down"),
    ".agents/slop/bullets/REPLACEMENTS.md:73":   ("REAL", "mine: arrow is part of 'shim -> impl'"),
    ".agents/slop/notes/bend2-constraints.md:11548": ("REAL", "mine: 646 vs 647, subject ENDS \\n"),
    ".agents/slop/notes/compare/sz.md:26":       ("AMBIGUOUS", "mine: subject resolves to 2 paths"),
    ".agents/slop/quiescefix/REPORT.md:275":     ("AMBIGUOUS", "mine: a PLAN record, not an assertion"),
    ".agents/slop/quiescefix/REPORT.md:276":     ("AMBIGUOUS", "mine: a PLAN record, not an assertion"),
    ".agents/slop/literal-oracle-report.md:390": ("FALSE_POSITIVE", "mine: a RUN's stdout"),
    ".agents/slop/claimaudit2/REPORT.md:271":    ("FALSE_POSITIVE", "mine: quotes a COMMIT message"),
    ".agents/slop/notes/bend2-constraints.md:11635": ("FALSE_POSITIVE", "mine: quotes a comment"),
    ".agents/slop/guardfix/REPORT.md:18":        ("FALSE_POSITIVE", "mine: wc -l, no trailing \\n"),
    ".agents/slop/guardfix/REPORT.md:141":       ("FALSE_POSITIVE", "mine: wc -l, no trailing \\n"),
    ".agents/slop/residual/REPORT.md:138":       ("FALSE_POSITIVE", "mine: wc -l, no trailing \\n"),
    ".agents/slop/I64MUL.md:3":                  ("FALSE_POSITIVE", "mine: `2605 -> 2712` is a DELTA"),
    ".agents/slop/closure/REPORT.md:263":        ("FALSE_POSITIVE", "mine: `224 -> 326` is a DELTA"),
    ".agents/slop/envprecond/REPORT.md:200":     ("FALSE_POSITIVE", "mine: `343 -> 362` is a DELTA"),
}

# ---- the proposal: exactly two branches, both measured at M = 0.
PROPOSED = {"output": "output", "wc -l CAUSAL [NO KIND]": "wc -l basis"}

rows = [l.rstrip("\n").split("\t") for l in (HERE / "detail.rows").read_text().splitlines()]
has = re.compile(r"has (\d+) lines, claim says (\d+)")


def kinds_of(f):
  return [k.split("=")[0] for k in f[5].split("|") if k and k != "-"]


out, i = [], 0
for f in sorted(rows, key=lambda r: (r[0], r[1])):
  v, at, subj, ev, repro, kinds, sl = f
  ks = kinds_of(f)
  i += 1
  label, by = LABELS.get(at, ("", ""))
  prop = [PROPOSED[k] for k in ks if k in PROPOSED]
  takes = ", ".join(sorted(set(prop))) or "-"
  m = has.search(ev)
  tail = (f"splitlines={m.group(1)} claim={m.group(2)}" if m else ev)
  out.append("\t".join((str(i), v, takes, label or "UNLABELLED", tail)))

(HERE / "pricing.rows").write_text("".join(l + "\n" for l in out))

n = sum(1 for l in out if l.split("\t")[1] == "FAIL" and l.split("\t")[2] != "-")
m = sum(1 for l in out if l.split("\t")[1] == "PASS" and l.split("\t")[2] != "-")
print(f"pricing.rows: {len(out)} rows (every lane-D row, not only the FAIL ones)")
print(f"the TWO proposed branches together discharge {n} FAIL rows and {m} PASS rows")
lab = Counter(l.split("\t")[3] for l in out if l.split("\t")[1] == "FAIL")
print(f"labels over the 66 FAIL rows: {dict(lab)}")
tak = Counter((l.split("\t")[1], l.split("\t")[3]) for l in out if l.split("\t")[2] != "-")
print(f"labels among rows the PROPOSED pair takes: {dict(tak)}")

# ---- THE FULL UNION, i.e. every candidate priced in priceD.out, priced on LABELS.  A union
# can be worse than its best part, so it gets its own M.
union = [f for f in rows if f[5] != "-"]
ul = Counter((f[0], LABELS.get(f[1], ("UNLABELLED", ""))[0]) for f in union)
print(f"\nFULL UNION of every priced candidate: {len(union)} rows taken "
      f"of {len(rows)} lane-D rows")
print(f"  by verdict x label: {dict(ul)}")
print("  the REAL rows the FULL union would silence:")
for f in union:
  if LABELS.get(f[1], ("", ""))[0] == "REAL":
    print(f"    {f[1]:<44} {f[5]}")