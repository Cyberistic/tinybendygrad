#!/usr/bin/env python3
"""Price lane D's missing classifier from `verdicts.rows` + one EXTRACTION pass.

NOTHING here re-judges a claim: lane D verdicts are read from the rows file the prior unit
wrote.  This only re-derives the FIELDS the rows file does not carry -- the `gap` between the
subject and the numeric span, the exact span, and whether the subject is newline-terminated --
by calling the census's OWN extractor (`prose` + `lane_bcd`) and its OWN vocabulary
(`OUTPUT`, `COMMAND`, `quoted_spans`), so no regex here is a second copy.

usage: priceD.py <verdicts.rows>
"""
import importlib.util
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("cites", ROOT / "checks/cites-census.py")
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)

HEAD = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True,
                      text=True).stdout.strip()

FIELDS = ("lane", "kind", "verdict", "at", "subject", "needle_kind", "evidence")
raw = [l.split("\t") for l in Path(sys.argv[1]).read_text().splitlines()]
D = [dict(zip(FIELDS, f)) for f in raw if f[0] == "D"]
DF = [f for f in D if f["verdict"] == "FAIL"]
DP = [f for f in D if f["verdict"] == "PASS"]
print(f"HEAD {HEAD}")
print(f"lane D population {len(D)} = FAIL {len(DF)} + PASS {len(DP)} + "
      f"REFUSED {len(D) - len(DF) - len(DP)}")

# ---- ONE extraction pass over lane D's distinct citing files, keyed (file, at).
want: dict[str, set[str]] = {}
for f in D:
  rel, _, at = f["at"].rpartition(":")
  want.setdefault(rel, set()).add(at)
got: dict[tuple[str, str], dict] = {}
for rel in sorted(want):
  try:
    text = (ROOT / rel).read_text(errors="replace")
  except OSError:
    continue
  claims, _ = cc.lane_bcd(rel, cc.prose(rel, text))
  for c in claims:
    if c["lane"] == "D" and str(c.get("at")) in want[rel]:
      got[(rel, str(c["at"]))] = c
for v, name in ((DF, "FAIL"), (DP, "PASS")):
  k = sum(1 for f in v if (f["at"].rpartition(":")[0], f["at"].rpartition(":")[2]) in got)
  print(f"re-extraction at THIS HEAD reproduces {k}/{len(v)} lane-D {name} rows "
        f"from {len(want)} citing files (rows file written at a DIFFERENT HEAD)")


def subject_state(rel: str) -> tuple[int | None, bool | None]:
  """(splitlines, ends_with_newline), via the census's OWN resolver."""
  p = ROOT / rel
  if not p.is_file():
    hit = cc.suffix_index().get("/" + rel)
    if hit is None or len(hit) != 1 or not (ROOT / hit[0]).is_file():
      return None, None
    p = ROOT / hit[0]
  raw_text = p.read_text(errors="replace")
  return len(raw_text.splitlines()), raw_text.endswith("\n")


def cited_line(f: dict) -> str:
  rel, _, at = f["at"].rpartition(":")
  if not at.isdigit():
    return ""
  try:
    return (ROOT / rel).read_text(errors="replace").splitlines()[int(at) - 1]
  except (OSError, IndexError, ValueError):
    return ""


def in_quote(line: str, num: int) -> bool:
  """Is the claimed number inside a paired backtick or double-quote span?  The census's own
  `quoted_spans` supplies the pairs, so the delimiter rule is not restated here."""
  return any(re.search(rf"(?<![\d,]){num}(?![\d,])", span) for _, _, span in cc.quoted_spans(line))


# ---- CANDIDATE KINDS.  Each names the needle_kind branch it borrows, or says NONE.
def k_output(c, line):
  """`output` -- `->` / `rc=` after the path claims a RUN, not a file.  Two readings:
  GAP (the census's own adjacency window) and LINE (an upper bound)."""
  if cc.OUTPUT.search(c.get("gap", "")):
    return "gap"
  return "line" if cc.OUTPUT.search(line) else ""


def k_command(c, line):
  """`command` -- the number is a COMMAND'S OUTPUT.  The census's `COMMAND` vocabulary,
  widened from `the needle IS a command` to `a command produced the number`."""
  return "line" if cc.COMMAND.search(line) else ""


def k_quoted(c, line):
  """`fragment` -- the number is QUOTED material: prose ABOUT a claim, not the claim.
  DELIMITER-CARRIED, which is `fragment`'s own epistemics (the delimiters, not the span,
  decide), so this is a widening of an existing branch, not a new kind."""
  return "quoted" if in_quote(line, c["num"]) else ""


def k_celllabel(c, line):
  """`cell-label` -- a number in a table cell is a RECORD, and a record has no predicate."""
  return "cell" if line.lstrip().startswith("|") else ""


def k_wcl(c, line):
  """NO KIND IN `needle_kind`.  A MEASUREMENT-BASIS refusal, and lane D already has three
  (`unit`, `delta`, `expired-anchor`).  `wc -l` counts NEWLINES; `splitlines()` also counts a
  final unterminated line, so the two differ by exactly 1 iff the subject lacks a trailing
  newline -- which is what makes this CAUSAL rather than a bare `claim+1` coincidence."""
  n, nl = c["_n"], c["_nl"]
  if n is None or n != c["num"] + 1:
    return ""
  return "explained(no trailing \\n)" if nl is False else "UNEXPLAINED(subject ends \\n)"


def k_wcl_causal(c, line):
  """THE SAME RULE WITH ITS CAUSAL TEST.  `claim+1` alone coincides with a real off-by-one;
  `claim+1 AND the subject lacks a trailing newline` is what `wc -l` actually means, because
  `splitlines()` counts a final unterminated line and `wc -l` does not."""
  n, nl = c["_n"], c["_nl"]
  return "causal(no trailing \\n)" if n is not None and n == c["num"] + 1 and nl is False else ""


# `OUTPUT` is `->|\brc\s*=|\bexit\s*=`, all ASCII.  A report that writes the arrow as a
# unicode character states the SAME claim and the branch cannot see it: MEASURED below, that
# one character class is the whole difference between `output` firing on 1 row and on 2.
ARROW = re.compile("→|⇒|↦|⟶")
FATARROW = re.compile("=>|-->|==>")


def k_output_uni(c, line):
  """`output`, plus the unicode arrows.  The SAME kind over a wider alphabet, NOT a new kind."""
  if cc.OUTPUT.search(c.get("gap", "")) or ARROW.search(c.get("gap", "")):
    return "gap"
  return "line" if cc.OUTPUT.search(line) or ARROW.search(line) else ""


def k_output_fat(c, line):
  """`output` plus unicode arrows PLUS `=>`.  Priced SEPARATELY because `=>` is an ordinary
  operator in this tree's prose and may be the whole of the widening."""
  if cc.OUTPUT.search(c.get("gap", "")) or ARROW.search(c.get("gap", "")) \
     or FATARROW.search(c.get("gap", "")):
    return "gap"
  return "line" if cc.OUTPUT.search(line) or ARROW.search(line) \
      or FATARROW.search(line) else ""


CANDS = (("output", k_output), ("output+UNICODE ARROW", k_output_uni),
         ("output+UNICODE+`=>`", k_output_fat),
         ("command", k_command), ("fragment(quoted)", k_quoted),
         ("cell-label", k_celllabel), ("wc -l claim+1 [NO KIND]", k_wcl),
         ("wc -l CAUSAL [NO KIND]", k_wcl_causal))


def key(f):
  return (f["at"].rpartition(":")[0], f["at"].rpartition(":")[2])


# ---- attach the re-derived fields.
for f in D:
  c = got.get(key(f))
  f["_repro"] = c is not None
  f["_line"] = cited_line(f)
  if c:
    c["_n"], c["_nl"] = subject_state(c["subject"])
    f["_n"], f["_nl"] = c["_n"], c["_nl"]
    f["_gap"] = c.get("gap", "")

print("\n--- candidate kinds on lane D (N = FAIL retired, M = PASS silenced) ---")
print(f"{'candidate':<26}{'N':>5}{'M':>5}   breakdown of N over 66 FAIL")
for name, pred in CANDS:
  n = [f for f in DF if f["_repro"] and pred(got[key(f)], f["_line"])]
  m = [f for f in DP if f["_repro"] and pred(got[key(f)], f["_line"])]
  detail = Counter(pred(got[key(x)], x["_line"]) for x in n)
  print(f"{name:<26}{len(n):>5}{len(m):>5}   {dict(detail)}")

hit = [f for f in DF if f["_repro"] and
       any(pred(got[key(f)], f["_line"]) for _, pred in CANDS)]
mhit = [f for f in DP if f["_repro"] and
        any(pred(got[key(f)], f["_line"]) for _, pred in CANDS)]
print(f"\nUNION: FAIL discharged {len(hit)}/{len(DF)} (surviving as `text` "
      f"{len(DF) - len(hit)}/{len(DF)}); PASS silenced {len(mhit)}/{len(DP)}")
print(f"UNION over rows the re-extraction reproduced: "
      f"{sum(1 for f in DF if f['_repro'])}/{len(DF)} FAIL, "
      f"{sum(1 for f in DP if f['_repro'])}/{len(DP)} PASS")

expl = [f for f in DF if f["_repro"] and
        k_wcl(got[key(f)], f["_line"]) == "explained(no trailing \\n)"]
unex = [f for f in DF if f["_repro"] and
        k_wcl(got[key(f)], f["_line"]) == "UNEXPLAINED(subject ends \\n)"]
print("\n--- SAFETY of the wc -l rule, over the reproduced FAIL rows ---")
print(f"claim+1 AND subject lacks a trailing newline (convention EXPLAINS): {len(expl)}")
print(f"claim+1 AND subject ENDS with a newline (rule CANNOT explain):       {len(unex)}")
for f in expl + unex:
  print(f"    {f['at']}  {f['evidence']}")

anch = [f for f in DF if cc.ISO.search(f["_line"])]
print(f"\n--- anchors ---\nFAIL rows whose citing line carries an ISO date: {len(anch)}/{len(DF)}")
for f in anch:
  print(f"    {f['at']}  {f['_line'].strip()[:110]}")

# ---- VALIDITY OF MY OWN `_n`.  The `wc -l` price depends on a line count I measured at a
# LATER HEAD than the census did, so it is only evidence if it agrees with the count the
# census wrote into its own evidence string.  Disagreements are named, not smoothed.
HAS = re.compile(r"has (\d+) lines")
ok = bad = 0
for f in D:
  m = HAS.search(f["evidence"])
  if not m or f.get("_n") is None:
    continue
  if int(m.group(1)) == f["_n"]:
    ok += 1
  else:
    bad += 1
    print(f"    COUNT DRIFT {f['verdict']} {f['at']}  census={m.group(1)} mine={f['_n']}  "
          f"subject={f['subject']}")
print(f"\n--- validity of MY subject line count vs the census's own evidence ---\n"
      f"agrees {ok}, DISAGREES {bad} (of {ok + bad} comparable rows)")

# ---- per-row detail, so pricing.rows has a witness per row.
# *** BIND `kinds` IN THE UNPACK. ***  An earlier revision wrote `for f, _ in out` and
# referenced `kinds` inside the generator, which is a FREE VARIABLE resolved at consumption
# time -- so every row carried the LAST row's kinds, and the row file said `output` fired on
# 66/66 FAIL rows while the same script's own priced table said 1.  The table was right and
# the file was wrong; a generator that reads a loop variable it did not bind is a second
# copy of the answer with no generator.
out = []
for f in sorted(D, key=lambda f: (f["verdict"], f["at"])):
  kinds = [f"{n}={pred(got[key(f)], f['_line'])}" for n, pred in CANDS
           if f["_repro"] and pred(got[key(f)], f["_line"])]
  out.append((f, kinds))
Path(".agents/slop/citeslaneD/detail.rows").write_text("".join(
    f"{f['verdict']}\t{f['at']}\t{f['subject']}\t{f['evidence']}\t"
    f"repro={'y' if f['_repro'] else 'n'}\t{'|'.join(kinds) or '-'}\t"
    f"splitlines={f.get('_n')} nl={f.get('_nl')}\n" for f, kinds in out))
print(f"\nwrote .agents/slop/citeslaneD/detail.rows ({len(out)} lane-D rows)")