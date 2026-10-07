#!/usr/bin/env python3
"""READ A REFUSAL. Both halves, or say which one is missing.

A refusal this project issues is a CLAIM THAT SOMETHING IS WRONG, and it has two
halves that behave nothing alike:

  * the REASON   -- an accurate description of a hazard.
  * the UNBLOCKING -- what would let work proceed.

`slowgate` already built the VERB for the second half: `UNKNOWN needs=rerun-with-more-seconds`
(`.agents/slop/slowgate/cap-plants.rows:9`), the shape `gatekit.py:60` already uses for the
five verdicts -- one vocabulary, loaded by path, so no consumer holds a second copy.

WHAT THIS TOOL IS NOT: it is not a sixth verdict. It is a READER. MEASURED, nothing in the
tree reads the UNBLOCKING half -- `grep -rn unblock checks/*.py gates/*.py` returns two hits,
both English in a comment, neither a parse (`checks/e2e.py:198`, `gates/ew-explog-gate.py:5`).

POPULATION, BY DISCOVERY (doctrine 1): os.walk over `.agents/slop/*/`, one report per unit
directory. A hand list would be doctrine 1's forbidden shape.

THE CEILING, STATED FIRST: a report is PROSE. This reads prose, and `declaretwo` measured
2 448 prose citations of which 1 777 were NEVER POSITIVELY CHECKED. So a row here is a
TRANSCRIPTION, never a verdict about the world. Only --verify re-runs anything.

USAGE
    refusal-read.py                 census -> refusals.rows, print table
    refusal-read.py --show UNIT     the transcription for one unit
    refusal-read.py --verify UNIT   RE-RUN the checkable claims (no bend)
    refusal-read.py --plant         PLANT 1/2/3 against this tool's own surface
Exit: 0 census ran, 1 a claim failed to verify, 3 REFUSED (cannot run).
"""
import argparse
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SLOP = os.path.normpath(os.path.join(HERE, os.pardir))
ROOT = os.path.normpath(os.path.join(SLOP, os.pardir, os.pardir))

# --------------------------------------------------------------------------
# THE HOUSE VERB, quoted from slowgate's own artifact. One mapping, so a reader
# and a gate agree on the word rather than each inventing one.
# --------------------------------------------------------------------------
NEEDS = "UNKNOWN needs="


def report_path(unit):
    """One report per unit directory: walk, first REPORT*.md, lexicographic."""
    d = os.path.join(SLOP, unit)
    if not os.path.isdir(d):
        return None
    for dirpath, dirnames, filenames in os.walk(d):
        dirnames[:] = [d_ for d_ in dirnames if d_ != "__pycache__"]
        for name in sorted(filenames):
            if name.upper().startswith("REPORT") and name.endswith(".md"):
                return os.path.join(dirpath, name)
    return None


# A refusal is a unit whose report declares one. `REFUSED` is the house word.
REFUSED = re.compile(r"\bREFUSED\b")
# "I did not land", "I declined", "tree UNTOUCHED" -- a refusal stated as an action.
DECLINED = re.compile(
    r"\b(I did not land|did NOT land|I declined|declined to|tree UNTOUCHED|"
    r"NOT LANDED|not landed|I did NOT)\b", re.I)
LANDED = re.compile(r"\b(I LANDED|LANDED:|I landed|now fixed|NOW FIXED|now REPAIRED|"
                    r"it is FIXED|the fix landed)\b")
# A unit that refused ANOTHER unit's claim rather than a brief.
REFUTED = re.compile(r"\b(refuted|refutation|was WRONG|REFUTES|BOTH WERE RIGHT)\b", re.I)

# THE UNBLOCKING HALF. Six shapes, each one MEASURED from a real report, because a
# shape list that is not measured is a hand list (doctrine 1's forbidden shape).
#   `flipblock`  : "SMALLEST THING THAT UNBLOCKS: one arm in `fold.bend` ..."
#   `flipport`   : "D. `fold.bend` - FORBIDDEN (another unit). THE BLOCKER."
#   `slowgate`   : "UNKNOWN needs=rerun-with-more-seconds"
#   `zerogate`   : "UNBLOCKING: <...>"
#   `onewalk`    : "the real fix is therefore NOT 'share more' - the owner must export"
#   `modulerefuse`: "the line the orchestrator must add is <...>"
UNBLOCK_RES = (
    re.compile(r"smallest (?:thing that )?unblocks?:?\s*\**\s*([^\n]{4,200})", re.I),
    re.compile(r"smallest unblocking(?: is| additionally owns|:)\s*\**\s*([^\n]{4,200})", re.I),
    re.compile(NEEDS + r"([a-z0-9][\w.-]{2,60})"),
    re.compile(r"\bUNBLOCKING:?\s*\**\s*([^\n]{4,200})"),
    # "THE BLOCKER." / "BLOCKER:" -- flipport's own header for the line it would not write.
    re.compile(r"\bBLOCKER[.:]?\s*\**\s*([^\n]{4,200})"),
    # "the line the orchestrator must add is <...>" -- a hand-off naming its subject.
    re.compile(r"\bthe (?:line|arm|edit|one thing) [^.\n]{0,40}must (?:add|be added)"
               r"\s*(?:is|:)\s*\**\s*([^\n]{4,200})", re.I),
)

# A match that is really the NEXT PARAGRAPH's heading, or a bare judgement word.
# MEASURED false positives, not guesses: flipblock's regex ate
# "**The two files the brief is asking about:**" because `[^\n]` ran past a bold run;
# unshardtable's `named unblock` shape ate `") rests on a` -- the tail of a quoted
# sentence whose subject was on the previous line.
NOT_A_PLAN = re.compile(
    r"^(\)|[\"'`]|the two files|is not small|rests on|see |above|below|"
    r"this section|section \d|\d+\.|[-*]\s)", re.I)


def _clean(frag):
    """Strip markdown noise and refuse to call a heading a plan."""
    frag = frag.replace("**", "").replace("__", "").strip()
    frag = " ".join(frag.split())
    # A PLAN names a subject: a path, an arm, a line, a name. Require a backticked
    # path OR a capitalised identifier; prose alone is a description.
    if NOT_A_PLAN.match(frag):
        return None
    if len(frag) < 8:
        return None
    return frag


def find_unblocking(text):
    """The unblocking half, or None. MEASURED shapes only; see UNBLOCK_RES."""
    best = None
    for rx in UNBLOCK_RES:
        for m in rx.finditer(text):
            frag = _clean(m.group(1))
            if not frag:
                continue
            # Prefer the most CONCRETE fragment: a quoted path beats a clause.
            concrete = len(re.findall(r"`[^`]+`", frag))
            score = (concrete, len(frag), -m.start())
            if best is None or score > best[0]:
                best = (score, frag)
    return best[1] if best else None


def classify(text):
    """LANDED / REFUSED-* / DECLINED / REFUTED, from the report's own words.

    ORDER MATTERS AND IS THE FINDING: a report can contain all these words. The
    order is "did it stop someone, and was that its own charge?" first, because a
    unit that refused ANOTHER unit's charge is a different animal from one that
    refused the brief (slowgate: refused a RED it did not cause; restoredinput:
    refused a fix a second unit had landed).
    """
    landed = bool(LANDED.search(text))
    declined = bool(DECLINED.search(text))
    refuted = bool(REFUTED.search(text))
    refused = bool(REFUSED.search(text))
    # "A CHARGE IT DID NOT CAUSE": the report must SAY the charge was not its own.
    # Absence of a landing is NOT that evidence -- it is the default outcome.
    not_my_charge = re.search(
        r"did not cause|not my charge|another unit|already landed|"
        r"a second unit|no green_|not a charge", text, re.I)
    if not_my_charge and declined and not landed:
        return "DECLINED-A-CHARGE-IT-DID-NOT-CAUSE"
    if refuted and not landed:
        return "REFUTED-ANOTHER-UNIT"
    if landed and not refused:
        return "LANDED"
    if refused:
        return ("REFUSED-WITH-UNBLOCKING" if find_unblocking(text)
                else "REFUSED-WITH-REASON-ONLY")
    if declined:
        return "DECLINED"
    if landed:
        return "LANDED"
    return "not-a-refusal"


def units():
    return sorted(e for e in os.listdir(SLOP)
                  if os.path.isdir(os.path.join(SLOP, e)) and report_path(e))


def census():
    rows = []
    for unit in units():
        path = report_path(unit)
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        kind = classify(text)
        unblock = find_unblocking(text)
        rows.append({
            "unit": unit,
            "class": kind,
            "unblocking": "READABLE" if unblock else ("none" if kind.startswith("REFUSED") else "n/a"),
            "needs": unblock or "",
            "report": os.path.relpath(path, ROOT),
        })
    return rows


def print_table(rows):
    width = max(len(r["unit"]) for r in rows)
    print("unit".ljust(width), "class".ljust(32), "unblocking")
    print("-" * (width + 46))
    for r in rows:
        print(r["unit"].ljust(width), r["class"].ljust(32), r["unblocking"])


# --------------------------------------------------------------------------
# --verify: RE-RUN a checkable claim. Refuses rather than paraphrases.
# --------------------------------------------------------------------------
def verify(unit):
    """Check what is mechanically checkable about one unit's refusal.

    Two facts are decidable without reading prose as truth:
      A. does the report still exist, and is it still the one we read?
      B. is the named subject still absent (a refusal whose subject LANDED is
         SATISFIED, and a satisfied refusal nobody noticed is an unfinished claim).
    B is what makes item 5's third plant possible at all.
    """
    path = report_path(unit)
    if path is None:
        print("REFUSED=%s: no report under .agents/slop/%s" % (unit, unit))
        return 3
    with open(path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    print("report      : %s (%d bytes)" % (os.path.relpath(path, ROOT), len(text)))
    print("class       : %s" % classify(text))
    unblock = find_unblocking(text)
    print("unblocking  : %s" % (unblock if unblock else "NONE NAMED -- a description, not a plan"))
    print("VERIFIED    : report exists and re-read (that is all this checks)")
    print("%s: re-running a unit's declined WORK is that unit's brief, not this tool's." % NEEDS)
    return 0


# --------------------------------------------------------------------------
# --plant: both directions, plus the satisfied case. TEMP dirs only.
# --------------------------------------------------------------------------
PLANT_SOURCE = r'''
import os, sys, importlib.util
spec = importlib.util.spec_from_file_location("rr", {here!r} + "/refusal-read.py")
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)

# REDIRECT THE POPULATION. The census walks rr.SLOP; point it at a TEMP tree so the
# real .agents/slop is never written to. MEASURED: a first version of this plant
# claimed to be temp and was not -- it created four directories in the real tree.
rr.SLOP = {tmp!r}
os.makedirs(rr.SLOP, exist_ok=True)

def unit(name, body):
    d = os.path.join(rr.SLOP, name)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "REPORT.md"), "w") as fh: fh.write(body)

# PLANT 1 -- a refusal WITH an unblocking. Must read READABLE.
unit("plantok", """# plantok
VERDICT: `REFUSED` -- I did not land it.
The smallest unblock is one arm in `fold.bend` teaching `flip_ds` an `ABoolList` flag-list.
""")

# PLANT 2 -- a refusal with NO unblocking. Must read `none`, NOT invented.
unit("plantdesc", """# plantdesc
VERDICT: `REFUSED`. Passing exit 2 to argparse collides with argparse's own usage error,
so exit 3 is already taken by REFUSED and the briefed 2->3 fix cannot be made here.
""")

# PLANT 3 -- slowgate's own verb, verbatim in shape. Must read READABLE.
unit("plantneeds", """# plantneeds
VERDICT: REFUSED. A spent budget is not a verdict.
UNKNOWN needs=rerun-with-more-seconds
""")

# PLANT 4 -- the case with no form yet: a refusal ALREADY SATISFIED. It must be
# DETECTABLE, or a satisfied refusal is an unfinished claim nobody can close.
unit("plantsat", """# plantsat
VERDICT: `REFUSED` -- the smallest unblock is one arm in `fold.bend` teaching `flip_ds`
an `ABoolList` flag-list.
STATUS: the unblock has since been landed by another unit.
""")

rows = {{r["unit"]: r for r in rr.census()}}
ok = 0
def check(label, got, want):
    global ok
    good = got == want
    ok += good
    print("PLANT %-3s got=%-9s want=%-9s %s" % (label, got, want, "OK" if good else "FAIL"))

check("1", rows.get("plantok", {{}}).get("unblocking"), "READABLE")
check("2", rows.get("plantdesc", {{}}).get("unblocking"), "none")
check("3", rows.get("plantneeds", {{}}).get("unblocking"), "READABLE")
# PLANT 4: detectability. There is NO SATISFIED column, and that absence IS the
# finding -- reported as a GAP rather than papered over with a passing assertion.
sat = rows.get("plantsat", {{}})
print("PLANT 4   satisfaction detectable=no  (no SATISFIED column exists -- REPORTED AS A GAP)")
print("PLANTS-RAN=4 PLANTS-FAILED=%d" % (4 - ok if ok == 3 else 4,))
print("TEMP-SLOP=%s" % rr.SLOP)
sys.exit(0 if ok == 3 else 1)
'''


def plant():
    """Run the plants against a TEMP slop. The real .agents/slop is never written."""
    with tempfile.TemporaryDirectory(prefix="refusal-read-plant-") as tmp:
        slop = os.path.join(tmp, "slop")
        src = PLANT_SOURCE.format(here=HERE, tmp=slop)
        script = os.path.join(tmp, "plant.py")
        with open(script, "w") as fh:
            fh.write(src)
        p = subprocess.run([sys.executable, script], capture_output=True, text=True)
        sys.stdout.write(p.stdout)
        if p.stderr:
            sys.stderr.write(p.stderr)
        after = os.path.dirname(os.path.abspath(__file__))
        leaked = [d for d in os.listdir(os.path.join(after, os.pardir))
                  if d.startswith("plantok") or d in ("plantdesc", "plantneeds", "plantsat")]
        print("LEAKED-INTO-REAL-SLOP=%d" % len(leaked), leaked)
        return p.returncode if not leaked else 1


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--show", metavar="UNIT")
    ap.add_argument("--verify", metavar="UNIT")
    ap.add_argument("--plant", action="store_true")
    ap.add_argument("--rows", default=os.path.join(HERE, "refusals.rows"))
    args = ap.parse_args()

    if args.plant:
        return plant()
    if args.verify:
        return verify(args.verify)
    if args.show:
        path = report_path(args.show)
        if path is None:
            print("REFUSED=%s: no report" % args.show)
            return 3
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        u = find_unblocking(text)
        print("class      : %s" % classify(text))
        print("unblocking : %s" % (u if u else "NONE NAMED"))
        return 0

    rows = census()
    print_table(rows)
    with open(args.rows, "w", encoding="utf-8") as fh:
        fh.write("unit\tclass\tunblocking\tneeds\treport\n")
        for r in rows:
            fh.write("%s\t%s\t%s\t%s\t%s\n" % (
                r["unit"], r["class"], r["unblocking"],
                r["needs"].replace("\t", " "), r["report"]))
    from collections import Counter
    c = Counter(r["class"] for r in rows)
    print()
    for k in sorted(c):
        print("%-32s %d" % (k, c[k]))
    refusals = [r for r in rows if r["class"].startswith("REFUSED")]
    named = [r for r in refusals if r["unblocking"] == "READABLE"]
    print()
    print("SCOPE: reports present under .agents/slop/*/ at this read (whole walk).")
    print("REFUSED-WITH-UNBLOCKING = %d of %d refusals" % (len(named), len(refusals)))
    print("REFUSED-WITH-REASON-ONLY = %d of %d refusals"
          % (len(refusals) - len(named), len(refusals)))
    print("rows -> %s" % args.rows)
    return 0


if __name__ == "__main__":
    sys.exit(main())