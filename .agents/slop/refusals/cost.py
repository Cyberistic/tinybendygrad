"""What did a refusal COST? Time -- with the rule that produced each number.

Two sources, and the distinction is the whole point:
  declared  -- a duration the report states in its own prose (a clock range, "294 s").
  mtime     -- the span between a unit's earliest and latest artifact on disk. This is
               a LOWER BOUND and an UPPER bound on nothing: a unit that ran in a
               minute leaves a minute-wide span, and a unit whose files were edited
               days apart leaves a wide one that is not its runtime.

A duration harvested by REGEX out of prose is not a measurement, and this file was
wrong three times before it was right once: `quiesce`'s "8 h" is a census WINDOW over
the whole tree, `indextree`'s "879s" is the tail of "1.879s", and `modulerefuse`'s
"40 min" is a delta between two readings of the same question, not its own runtime.
Each is rejected here by an explicit guard, because a number quoted without the rule
that produced it is the failure `AGENTS.md` documents at `elf.bend` (353 / 331 / 246).

Nothing is written except this file's own .rows/.out siblings.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SLOP = os.path.normpath(os.path.join(HERE, os.pardir))

CLOCK = re.compile(r"\b(\d{1,2}):(\d{2})\s*[-–—]\s*(\d{1,2}):(\d{2})\b")
# A duration that is plainly ABOUT THE UNIT: "cost N s", "ran for N s", "N s under".
DUR = re.compile(r"\b(\d{3,5})\s*(?:s\b|sec\b|seconds?)\b")
MIN = re.compile(r"\b(\d{1,3})\s*(?:m\b|min\b|minutes?)\b")
HOUR = re.compile(r"\b(\d(?:\.\d)?)\s*(?:h\b|hr\b|hours?)\b")

# REJECTIONS, each MEASURED against a real sentence in a real report.
REJECT = (
    # "An 8 h mtime census" / "(8 h census)" -- a WINDOW over the tree, not a runtime.
    (re.compile(r"(?:census|window|span|bucket|histogram|mtime)", re.I), "census-window-not-runtime"),
    # "1.879s" -- the regex must not take the tail of a decimal.
    (re.compile(r"\d\.\d"), "tail-of-a-decimal"),
    # "40 minutes later" / "904 min" as a FILE AGE / "reported 43 minutes" about ANOTHER unit.
    (re.compile(r"\blater\b|\bago\b|\bpreviously\b|\bearlier\b|\bdelta\b|\bthan\b", re.I),
     "delta-not-runtime"),
    (re.compile(r"\bnewest file\b|\bfile age\b|\bcold\b", re.I), "file-age-not-runtime"),
    (re.compile(r"\breported\b|\bclaimed\b", re.I), "another-units-claim-not-runtime"),
    # A bare count that happens to precede "seconds" ("0 rows, 205 seconds").
    (re.compile(r"^\s*\d+\s+(?:rows?|files?|gates?|units?)\b", re.I), "count-not-runtime"),
    # A TABLE ROW: "| < 6 h | 5 | 104 |" -- a histogram bucket, not a duration.
    (re.compile(r"^\s*[-*|]|\|\s*\d"), "table-row-not-runtime"),
    # "a gate loop held it for ~4 min" -- the WAIT for another process, not this unit.
    (re.compile(r"\bheld it\b|\bwait(?:ed|ing)?\b|\bblocked (?:for|on)\b", re.I), "wait-not-runtime"),
)


def reports():
    for entry in sorted(os.listdir(SLOP)):
        d = os.path.join(SLOP, entry)
        if not os.path.isdir(d) or entry in {"__pycache__", "refusals"}:
            continue
        for dirpath, dirnames, filenames in os.walk(d):
            dirnames[:] = [d_ for d_ in dirnames if d_ != "__pycache__"]
            for name in sorted(filenames):
                if name.upper().startswith("REPORT") and name.endswith(".md"):
                    yield entry, os.path.join(dirpath, name)


def sentence_around(text, start, end):
    lo = max(0, text.rfind("\n", 0, start))
    hi = text.find("\n", end)
    return text[lo:hi if hi > 0 else len(text)]


def declared_seconds(text):
    """(seconds, evidence) for a duration that is provably the unit's own, or None."""
    cands = []
    for m in CLOCK.finditer(text):
        h1, m1, h2, m2 = (int(g) for g in m.groups())
        if (h2 * 60 + m2) <= (h1 * 60 + m1):
            continue
        cands.append(((h2 * 60 + m2 - h1 * 60 - m1) * 60, m.group(0), m, "clock-range"))
    for rx, div, kind in ((HOUR, 3600, "hours"), (MIN, 60, "minutes"), (DUR, 1, "seconds")):
        for m in rx.finditer(text):
            line = sentence_around(text, m.start(), m.end())
            for rx_reject, why in REJECT:
                if rx_reject.search(line):
                    break
            else:
                cands.append((int(float(m.group(1)) * div), m.group(0), m, kind))
    if not cands:
        return None, ""
    secs, ev, m, kind = max(cands, key=lambda t: t[0])
    return secs, "%s [%s] %s" % (ev, kind, " ".join(sentence_around(text, m.start(), m.end()).split())[:96])


def mtime_span(unit):
    lo = hi = None
    for dirpath, dirnames, filenames in os.walk(os.path.join(SLOP, unit)):
        dirnames[:] = [d for d in dirnames if d != "__pycache__"]
        for name in filenames:
            if name.endswith((".py", ".md", ".rows", ".out", ".err", ".tsv")):
                t = os.path.getmtime(os.path.join(dirpath, name))
                lo = t if lo is None else min(lo, t)
                hi = t if hi is None else max(hi, t)
    return lo, hi


def refusals():
    """The population, loaded from the READER, not re-listed here."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "rr", os.path.join(HERE, "refusal-read.py"))
    rr = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rr)
    return [r for r in rr.census() if r["class"].startswith("REFUSED") or r["class"].startswith("DECLINED")]


def main():
    rows = []
    for unit, path in reports():
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        secs, ev = declared_seconds(text)
        lo, hi = mtime_span(unit)
        rows.append((unit, secs, ev, hi - lo, path))

    print("=== DECLARED DURATIONS THAT SURVIVED THE GUARDS ===")
    kept = [(u, s, e) for u, s, e, _, _ in rows if s]
    for u, s, e in sorted(kept, key=lambda t: -t[1]):
        print("  %-16s %6d s   %s" % (u, s, e))
    print("KEPT=%d of %d reports" % (len(kept), len(rows)))
    print()
    print("=== MTIME SPANS (a lower bound, not a runtime) ===")
    spans = sorted(((u, sp) for u, _, _, sp, _ in rows), key=lambda t: -t[1])
    for u, sp in spans[:8]:
        print("  %-16s %7.0f s" % (u, sp))
    lo = min(sp for _, sp in spans)
    hi = max(sp for _, sp in spans)
    print("MTIME-SPAN-MIN=%.0f MAX=%.0f over %d reports" % (lo, hi, len(spans)))
    print()
    print("=== COST OF THE REFUSALS NAMED IN THE BRIEF ===")
    want = ("flipblock", "flipport", "unshardtable", "unshardfold", "exitcode",
            "restoredinput", "declaretwo", "onewalk", "slowgate", "modulerefuse")
    by = {u: (s, e, sp) for u, s, e, sp, _ in rows}
    total = 0
    for u in want:
        if u not in by:
            print("  %-16s NO REPORT (evidence-only: %s)"
                  % (u, sorted(os.listdir(os.path.join(SLOP, u)))[:3] if os.path.isdir(os.path.join(SLOP, u)) else "absent"))
            continue
        s, e, sp = by[u]
        src = ("declared %ds" % s) if s else ("mtime-span %.0fs (lower bound)" % sp)
        if s:
            total += s
        print("  %-16s %s" % (u, src))
    print("BRIEF-DECLARED-TOTAL=%d s" % total)
    return 0


if __name__ == "__main__":
    sys.exit(main())