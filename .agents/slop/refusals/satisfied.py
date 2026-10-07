"""Was a refusal's UNBLOCKING ever satisfied? And does naming one correlate with landing?

For each refusal the reader classified REFUSED-WITH-UNBLOCKING, take the backticked
path(s) the unblocking names and ask the TREE whether the subject is present. A
refusal whose subject is STILL absent is an open claim; one whose subject is now
present may be SATISFIED -- and a satisfied refusal nobody closes is exactly the
"a file says what it is and nothing believes it" shape.

Then the CORRELATION (item 3): units that LANDED something vs whether their report
named a restorable subject. Per the brief: the refusals that did not pay for
themselves are the ones that named no restorable subject.

NOTHING IS WRITTEN. Reads only. No bend. No shell.
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, os.pardir, os.pardir))

spec = importlib.util.spec_from_file_location("rr", os.path.join(HERE, "refusal-read.py"))
rr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rr)

PATHISH = re.compile(r"`([A-Za-z0-9_./+-]+\.[a-z]{1,4}(?::\d+)?)`")


def named_paths(frag):
    """Backticked things in the unblocking that LOOK like repo paths."""
    out = []
    for m in PATHISH.finditer(frag):
        p = m.group(1)
        if "/" in p or p.endswith((".bend", ".py", ".sh")):
            out.append(p.split(":")[0])
    return sorted(set(out))


def resolve(path):
    """Find the subject under the tree. Returns (found, where)."""
    base = os.path.basename(path)
    hits = []
    for top in ("tinybendygrad", "checks", "gates", "oracles"):
        root = os.path.join(ROOT, top)
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for name in filenames:
                if name == base:
                    hits.append(os.path.relpath(os.path.join(dirpath, name), ROOT))
    return bool(hits), hits[:2]


def main():
    rows = rr.census()
    refusals = [r for r in rows if r["class"].startswith("REFUSED")]
    named = [r for r in refusals if r["unblocking"] == "READABLE"]
    print("SCOPE: whole walk of .agents/slop/*/ at this read; %d refusals, %d with a"
          % (len(refusals), len(named)))
    print("       readable UNBLOCKING half.")
    print()
    print("=== UNBLOCKING-SATISFACTION SWEEP ===")
    satisfied = open_ = 0
    for r in named:
        paths = named_paths(r["needs"])
        print("\nunit      : %s" % r["unit"])
        print("unblocking: %s" % r["needs"][:120])
        if not paths:
            print("subjects  : NONE NAMED AS A PATH -- a description, not a hand-off")
            open_ += 1
            continue
        for p in paths:
            found, where = resolve(p)
            print("  %-28s %s" % (p, "PRESENT %s" % where if found else "ABSENT"))
            if found:
                satisfied += 1
            else:
                open_ += 1
    print()
    print("SUBJECTS-SATISFIED=%d  SUBJECTS-STILL-ABSENT=%d  over %d named refusals"
          % (satisfied, open_, len(named)))
    print()
    print("=== CORRELATION: does naming a subject go with LANDING? ===")
    landed = [r for r in rows if r["class"] == "LANDED"]
    print("LANDED reports (by this tool's own reader) = %d of %d reports"
          % (len(landed), len(rows)))
    print("  units:", ", ".join(r["unit"] for r in landed) or "none")
    print()
    print("CEILING: both numbers are TRANSCRIPTIONS of prose by regex. This script")
    print("re-runs nothing about the world except whether a named path is on disk.")
    return 0


if __name__ == "__main__":
    sys.exit(main())