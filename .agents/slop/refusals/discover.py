"""Population of tonight's REFUSAL claims, by DISCOVERY.

Doctrine 1: a population is (a) a generator's own declaration loaded by path,
(b) a directory walk, or (c) a regex over the tree's own write sites. A hand
list is not a population. This is (b): os.walk + endswith.

Emits `.rows`, one row per unit directory under .agents/slop that left a
report, with the verdict tokens that appear in that report's own bytes.
"""
import os
import re
import sys

SLOP = os.path.join(os.path.dirname(__file__), os.pardir)
SLOP = os.path.normpath(SLOP)

# Verdict vocabulary. `REFUSED` is the house word; the others are the
# neighbouring states this census must NOT fold into it.
TOKENS = (
    "REFUSED", "LANDED", "DECLINED", "UNBLOCKING", "SKIP", "DEAD", "REFUSED-WITH",
    "OUT OF SCOPE", "ALREADY FIXED", "SATISFIED",
)
# A report that never uses a verdict word is not a refusal claim; it is a
# finding. Recorded as VERDICT=none so the denominator is visible.
WORD = re.compile(r"\b(%s)\b" % "|".join(t.replace(" ", r"\s") for t in TOKENS))


def reports():
    """(b) DIRECTORY WALK. One report per unit directory, newest wins."""
    found = []
    for entry in sorted(os.listdir(SLOP)):
        unit = os.path.join(SLOP, entry)
        if not os.path.isdir(unit) or entry in {"__pycache__", "refusals"}:
            continue
        for dirpath, dirnames, filenames in os.walk(unit):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for name in sorted(filenames):
                if name.upper().startswith("REPORT") and name.endswith(".md"):
                    path = os.path.join(dirpath, name)
                    found.append((entry, path))
    return found


def verdict(text):
    counts = {}
    for m in WORD.finditer(text):
        counts[m.group(0)] = counts.get(m.group(0), 0) + 1
    if not counts:
        return "none"
    # A unit that says REFUSED more than any other verdict word is a refusal.
    top = max(counts.items(), key=lambda kv: kv[1])
    return top[0] if top[1] > 1 else "mention:" + ",".join(sorted(counts))


def span(unit):
    """Mtime span of the unit's report + scripts: a lower bound on cost."""
    lo = hi = None
    for dirpath, dirnames, filenames in os.walk(os.path.join(SLOP, unit)):
        dirnames[:] = [d for d in dirnames if d != "__pycache__"]
        for name in filenames:
            if name.endswith((".py", ".md", ".rows", ".out", ".err", ".tsv")):
                t = os.path.getmtime(os.path.join(dirpath, name))
                lo = t if lo is None else min(lo, t)
                hi = t if hi is None else max(hi, t)
    return lo, hi


def main():
    rows = []
    for unit, path in reports():
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        lo, hi = span(unit)
        rows.append({
            "unit": unit,
            "verdict": verdict(text),
            "bytes": len(text),
            "has_unblocking": "yes" if re.search(r"UNBLOCK|unblock", text) else "no",
            "first": lo or 0.0,
            "last": hi or 0.0,
            "report": os.path.relpath(path, SLOP),
        })
    rows.sort(key=lambda r: r["first"])
    for r in rows:
        print("unit=%s verdict=%s unblocking=%s bytes=%d span_s=%.0f report=%s"
              % (r["unit"], r["verdict"], r["has_unblocking"], r["bytes"],
                 r["last"] - r["first"], r["report"]))
    print("TOTAL-REPORTS=%d" % len(rows))
    refusals = [r for r in rows if r["verdict"] == "REFUSED"]
    print("REFUSED-VERB-REPORTS=%d" % len(refusals))
    for r in refusals:
        print("REFUSED-UNIT=%s" % r["unit"])
    print("NONE-VERDICT=%d" % sum(1 for r in rows if r["verdict"] == "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main())