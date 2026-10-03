#!/usr/bin/env python3
"""tree-verdict.py -- a tree verdict BUCKETED BY CAUSE, not by pass/fail.

WHY THIS EXISTS. `bend --check-only` emits ONE first line for four different worlds:

    ALL PROOFS CHECK                                            -> clean
    SOME PROOFS FAIL + "N defs rely on unsafe or foreign code"  -> a DECLARED seam
    SOME PROOFS FAIL + "N TODOs found" / "not a valid proof yet" -> a proof unfinished
    SOME PROOFS FAIL + "expected/observed/Location"              -> actually BROKEN

A single RED bucket conflates them, so a unit that reads it goes and fixes things that are
not broken -- which has already happened twice in one day. This script decides the bucket
from the ERROR TEXT, never from a hardcoded file list, and prints the evidence that
decided it.

A COMPILE ERROR PROPAGATES, and so does its blame. bend's `Location:` block gives a line
number and the source text at that line but NEVER NAMES THE FILE, so an error in one
shared datatype turns every one of its 76 importers red while the file you invoked looks
blameless. That is why `broken` is split in two, and why the owner is found by asking
WHICH FILE IN THE TREE HAS THAT SOURCE TEXT AT THAT LINE -- an answer from the evidence,
with `observed : {LAWS/spec.d0 : ...}` as an independent corroboration (the prefix names
the defining module, and it is absent exactly when the error is in the file itself).

READING THE ROW COUNT. Rows are counted on bend's STDOUT with its own two success
messages subtracted, because the error block lands on STDERR. A 0-ROW RESULT IS
INDISTINGUISHABLE FROM "NOT STARTED", so one.sh retries it and this script only
classifies after the cap. 0 rows is then split by a STATIC fact the run cannot supply:
does the source declare `def main`?  no -> `no-main` (a library, by design); yes ->
`no-rows`, which is a QUESTION, never a verdict.

READ-ONLY BY CONSTRUCTION. The only writes are to a scratch dir beside this script.
tinybendygrad/** and tinygrad/** are opened read-only, always: a tree-check harness that
edited in place cost another unit a whole file rewrite across a server restart.

    python3 .agents/slop/tree-verdict.py [-P 12] [--json] [--only SUBSTR]
"""
import argparse
import concurrent.futures as cf
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SCRATCH = os.path.join(HERE, "tv-scratch")
ROOTS = ("tinybendygrad", "examples")
ONE = os.path.join(HERE, "one.sh")

# bend's own success lines, on stdout. Anything else on stdout is a proof row.
BEND_MESSAGES = ("ALL PROOFS CHECK", "Use --verdict for mathematical validity.")

# A filename is not evidence, so these never decide a bucket. They only label a line
# `scratch?` so a reader can reconcile a file COUNT against another unit's: mutation
# scratch living inside the tree is counted by a naive `find`.
SCRATCH_RE = re.compile(r"(^_|probe|_work|\.mut\.)")

FOREIGN_RE = re.compile(r"(\d+) defs rely on unsafe or foreign code")
WIP_RE = re.compile(r"(\d+) TODOs found")
WIP_TAIL_RE = re.compile(r"not a valid proof yet")
LOC_RE = re.compile(r"^(\d+)>\| (.*)$", re.M)
MODPATH_RE = re.compile(r"observed : \{([A-Za-z_][A-Za-z0-9_/]*)\.")

BUCKETS = ("green", "no-main", "no-rows", "foreign-code-surface",
           "proof-in-progress", "broken-here", "broken-in-import", "no-verdict")


def bend_files(root):
    out = []
    for r in ROOTS:
        for dirpath, dirs, files in os.walk(os.path.join(root, r)):
            dirs[:] = sorted(d for d in dirs if d not in (".git", "__pycache__"))
            out += [os.path.join(dirpath, f)
                    for f in sorted(files) if f.endswith(".bend")]
    return sorted(out)


def corpus(root, paths):
    """{relpath: lines}, for attributing a Location block bend never labelled."""
    out = {}
    for p in paths:
        try:
            out[os.path.relpath(p, root)] = open(p, errors="ignore").read().splitlines()
        except OSError:
            pass
    return out


def declares_main(root, rel):
    with open(os.path.join(root, rel), errors="ignore") as fh:
        return "\ndef main" in fh.read()


def check_one(root, path):
    """Run one.sh in its own scratch dir; return the record plus the raw diagnostics."""
    rel = os.path.relpath(path, root)
    out = os.path.join(SCRATCH, rel.replace(os.sep, "_"))
    # `sh one.sh`, not `./one.sh`: a checkout that drops the exec bit must not become
    # a crash here. This tool's output matters more than its exit status.
    env = dict(os.environ, BEND_ROOT=root)
    proc = subprocess.run(["sh", ONE, rel, out], cwd=root, env=env,
                          capture_output=True, text=True)
    if not os.path.exists(ONE):
        sys.exit("missing %s -- tree-verdict.py refuses to guess a per-file checker" % ONE)
    try:
        rows, attempts, _first = proc.stdout.strip().split("\t")
    except ValueError:
        sys.exit("one.sh produced %r for %s (rc=%d): %s"
                 % (proc.stdout, rel, proc.returncode, proc.stderr.strip()[:200]))
    # check.err first: on FAILURE the error block is there and check.out is empty; on
    # SUCCESS check.err is empty and check.out holds the verdict. Concatenating in that
    # order yields the diagnostics either way, without branching on the verdict we are
    # in the middle of computing.
    diag = (open(os.path.join(out, "check.err"), errors="ignore").read() +
            open(os.path.join(out, "check.out"), errors="ignore").read())
    return rel, int(rows), int(attempts), diag


def compile_error(rel, diag, lines_by_file):
    """(bucket, detail) for a red that matches no declared-failure message.

    The owner is whichever file in the tree holds the offending source text at the
    offending line. If that is `rel`, the defect is here; otherwise this file only
    IMPORTS the broken one, and reporting it as broken here would send a unit to fix
    the wrong file.
    """
    exp = " ".join(re.findall(r"^- (?:expected|observed) : (.*)$", diag, re.M))
    at = LOC_RE.search(diag)
    if not at:
        return "broken-here", "%s -- no Location block; %s" % (
            rel, exp or " ".join(diag.split())[:90])
    lineno, text = int(at.group(1)), at.group(2).strip()
    homes = [p for p, ls in lines_by_file.items()
             if lineno <= len(ls) and ls[lineno - 1].strip() == text]
    hint = MODPATH_RE.search(diag)
    where = "%s:%d  %s" % (rel if rel in homes else ",".join(homes) or "UNKNOWN FILE",
                           lineno, text)
    if rel in homes:
        return "broken-here", "%s -- expected %s" % (where, exp)
    return "broken-in-import", "%s imports the owner; observed names %s" % (
        where, hint.group(1) if hint else "(no module prefix)")


def classify(root, rec, lines_by_file):
    """Bucket by CAUSE. `broken-*` is the residual: every red that matches a declared
    failure message is named, and one that matches none is a real defect."""
    rel, rows, attempts, diag = rec
    first = next((l for l in diag.splitlines() if l.strip()), "")

    if first == "ALL PROOFS CHECK":
        if rows:
            return "green", "rows=%d" % rows
        if declares_main(root, rel):
            return "no-rows", "main declared; 0 rows in %d attempts" % attempts
        return "no-main", "library: no `def main`; the verdict IS the first line"

    if first == "SOME PROOFS FAIL":
        m = FOREIGN_RE.search(diag)
        if m:
            names = re.findall(r"^- (\S+)", diag, re.M)
            # An imported name is written `../dtype.Dt.bf16`; a declared one `Dt.bf16`.
            own = [x for x in names if "/" not in x]
            return "foreign-code-surface", "N=%s, %s: %s" % (
                m.group(1),
                ("declares %d own" % len(own)) if own else ("propagates %d imported" % len(names)),
                ", ".join((own or names)[:3]))
        if WIP_RE.search(diag) or WIP_TAIL_RE.search(diag):
            n = WIP_RE.search(diag)
            # The MESSAGE decides; the filename is corroboration only, and is reported
            # as a note so a reader can see it was not what entered the bucket.
            return "proof-in-progress", "N=%s TODOs, unfinished%s" % (
                n.group(1) if n else "?",
                " (law/PROOF file)" if re.search(r"(PROOF|LAWS)", rel) else "")
        return compile_error(rel, diag, lines_by_file)

    return "no-verdict", "no diagnostics in %d attempts (bend died?)" % attempts


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("-P", type=int, default=12, help="parallel bend invocations")
    ap.add_argument("--attempts", type=int, default=6, help="0-row/flake retries")
    ap.add_argument("--only", default="", help="substring filter on the path")
    ap.add_argument("--root", default=REPO,
                    help="tree root; point it at a COPY to run a negative control")
    ap.add_argument("--json", action="store_true", help="machine-readable records")
    args = ap.parse_args()
    os.environ["ONE_ATTEMPTS"] = str(args.attempts)

    root = os.path.abspath(args.root)
    files = [f for f in bend_files(root) if args.only in os.path.relpath(f, root)]
    lines_by_file = corpus(root, files)
    os.makedirs(SCRATCH, exist_ok=True)
    with cf.ThreadPoolExecutor(args.P) as pool:
        out = [(r, classify(root, r, lines_by_file))
               for r in pool.map(lambda f: check_one(root, f), files)]

    if args.json:
        print(json.dumps([{"file": r[0], "rows": r[1], "attempts": r[2],
                           "cause": c[0], "evidence": c[1]} for r, c in out], indent=1))
        return 0

    for (rel, nrows, _, _), (cause, detail) in out:
        tag = "scratch?" if SCRATCH_RE.search(os.path.basename(rel)) else ""
        print("%-22s %6d rows  %-22s %s%s"
              % (cause, nrows, os.path.basename(rel), detail, "  [%s]" % tag if tag else ""))

    tally = {b: 0 for b in BUCKETS}
    for _, (cause, _) in out:
        tally[cause] += 1
    print("\n%d .bend files under %s" % (len(out), " + ".join(ROOTS)))
    for b in BUCKETS:
        if tally[b]:
            print("  %-22s %3d" % (b, tally[b]))

    roots = {}
    for (rel, _, _, _), (cause, detail) in out:
        if cause.startswith("broken"):
            roots.setdefault(detail, []).append(rel)
    if roots:
        print("\nBROKEN -- grouped by OWNER, because one defect reds every importer:")
        for detail, importers in sorted(roots.items(), key=lambda kv: -len(kv[1])):
            print("  %2d file(s) red from: %s" % (len(importers), detail))
            for rel in importers[:4]:
                print("        %s" % rel)
            if len(importers) > 4:
                print("        ... and %d more" % (len(importers) - 4))
    return 1 if tally["broken-here"] or tally["broken-in-import"] or tally["no-verdict"] else 0


if __name__ == "__main__":
    sys.exit(main())
