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
shared datatype turns all 76 of its importers red while the file you invoked looks
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
edited in place cost another unit a whole file rewrite across a server restart. Pass
`--root` to check a COPY instead, which is how the negative control is run.

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
# scratch living inside the tree is counted by a naive `find`. `^_[^_]` and not `^_`,
# because `__init__.bend` is a real package marker in this tree, not scratch -- an
# over-broad label is the same defect as a wrong bucket, only quieter.
SCRATCH_RE = re.compile(r"(^_[^_]|probe|_work|\.mut\.)")

FOREIGN_RE = re.compile(r"(\d+) defs rely on unsafe or foreign code")
# `TODOs?`: bend prints "1 TODO found", not "1 TODOs found". With `s` required, the count
# for a single unfilled law read as absent and printed "N=?" -- the evidence line was wrong
# exactly when it mattered most, one law from done.
WIP_RE = re.compile(r"(\d+) TODOs? found")
WIP_TAIL_RE = re.compile(r"not a valid proof yet")
IMPORT_RE = re.compile(r"import\s+\./(\S*?\.bend)")
MAIN_RE = re.compile(r"(?m)^def main\b")

LOC_RE = re.compile(r"^(\d+)>\| (.*)$", re.M)
GUTTER_RE = re.compile(r"^\s*(\d+) [|>] (.*)$", re.M)
MODPATH_RE = re.compile(r"observed : \{([A-Za-z_][A-Za-z0-9_/]*)\.")
PROOF_MEMBER_RE = re.compile(r"(^|/)(PROOF|LAWS)[0-9A-Za-z_.-]*\.bend$")
# IMPORT_RE requires `./`, so `import ../PROOF.bend` is invisible to it -- which is why the
# aggregate scored 0 member-imports and PROOF.bend won. This one sees both forms.
ANY_IMPORT_RE = re.compile(r"import\s+\.\.?(?:/\.\.)*/([A-Za-z0-9_./-]+\.bend)")

# (first_line, n_todos, aggregator relpath) for the proof SET, computed once in main().
_SET = [None, None, None]

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


def corpus(paths):
    """{relpath: lines}, for attributing a Location block bend never labelled."""
    out = {}
    for p in paths:
        try:
            out[os.path.relpath(p, ROOT[0])] = open(p, errors="ignore").read().splitlines()
        except OSError:
            pass
    return out


lines_by_file = {}


def declares_main(rel):
    return bool(MAIN_RE.search(open(os.path.join(ROOT[0], rel), errors="ignore").read()))


def main_origin(rel):
    """Where the `main` in scope comes from, or None if there is not one.

    A LITERAL `def main` IN THE SOURCE IS NOT THE SAME AS A MAIN IN SCOPE. Measured:
    `codegen/rewriter.bend` declares no main, yet appending one to it fails with
    "duplicate declaration: main" -- because `uop/ops.bend`, `uop/fold.bend` and
    `LAWS/spec.bend` all declare one and rewriter imports all three. It prints 0 rows
    and that is NOT the same situation as `helpers.bend`, which has no main anywhere in
    its import closure. Calling both "no main" is the same conflation this tool exists
    to stop, one level down.

    This walks the import GRAPH, so it reads from disk rather than from the swept
    corpus: `--only` truncates the corpus, and a walk that silently stops at the corpus
    edge reports every filtered file as a library.
    """
    if declares_main(rel):
        return "declared in this file"
    seen, stack, found = set(), [rel], None
    while stack:
        cur = stack.pop()
        if cur in seen:
            continue
        seen.add(cur)
        try:
            src = open(os.path.join(ROOT[0], cur), errors="ignore").read()
        except OSError:
            continue
        if found is None and MAIN_RE.search(src):
            found = cur
        stack += [os.path.normpath(os.path.join(os.path.dirname(cur), m))
                  for m in IMPORT_RE.findall(src)]
    return "inherited from %s" % found if found else None


def check_one(path):
    """Run one.sh in its own scratch dir; return the record plus the raw diagnostics."""
    rel = os.path.relpath(path, ROOT[0])
    out = os.path.join(SCRATCH, rel.replace(os.sep, "_"))
    # `sh one.sh`, not `./one.sh`: a checkout that drops the exec bit must not become
    # a crash here. This tool's output matters more than its exit status.
    proc = subprocess.run(["sh", ONE, rel, out], cwd=ROOT[0],
                          env=dict(os.environ, BEND_ROOT=ROOT[0]),
                          capture_output=True, text=True)
    # strip("\n") and not strip(): a file bend printed NOTHING for yields an empty last
    # field, and `.strip()` would eat the tab and hand back four fields.
    try:
        rows, attempts, distinct, voids, _verdict = proc.stdout.strip("\n").split("\t")
    except ValueError:
        sys.exit("one.sh produced %r for %s (rc=%d): %s"
                 % (proc.stdout, rel, proc.returncode, proc.stderr.strip()[:200]))
    # check.err first: on FAILURE the error block is there and check.out is empty; on
    # SUCCESS check.err is empty and check.out holds the verdict. Concatenating in that
    # order yields the diagnostics either way, without branching on the verdict we are
    # in the middle of computing.
    diag = (open(os.path.join(out, "check.err"), errors="ignore").read() +
            open(os.path.join(out, "check.out"), errors="ignore").read())
    return rel, int(rows), (int(attempts), int(distinct), int(voids)), diag


def proof_set_verdict(files):
    """The TODO count is a property of the SET, not of a file. `PROOF.bend` holds 16 of the
    34 proofs and `LAWS.bend` holds none, so run alone each reports TODOs that the aggregate
    does not have -- this file reported 3 reds for a set that reads ALL PROOFS CHECK.

    The aggregate is FOUND, not named: it is the file importing the most other bend files.
    A hardcoded `PROOF-ALL.bend` would be the hardcoded file list this tool exists to avoid,
    and would silently mis-bucket the day the set is renamed.
    Returns (first_line, n_todos, aggregator_relpath), or (None, None, None)."""
    counts = {}
    for f in files:
        try:
            body = open(f, errors="ignore").read()
        except OSError:
            continue
        imports = ANY_IMPORT_RE.findall(body)
        # Count only imports that are THEMSELVES set members. Plain "most imports" ties:
        # PROOF-ALL and PROOF.bend each import 2, and the tie went to the wrong file, which
        # reported the set as 18 TODOs. The aggregate is the member that imports MEMBERS.
        score = sum(1 for m in imports if PROOF_MEMBER_RE.search(m))
        if score > counts.get(f, -1):
            counts[f] = score
    agg = max(counts, key=counts.get) if counts else None
    if agg is None:
        return None, None, None
    proc = subprocess.run(["sh", ONE, os.path.relpath(agg, ROOT[0]),
                           os.path.join(SCRATCH, "_aggregate")], cwd=ROOT[0],
                          env=dict(os.environ, BEND_ROOT=ROOT[0]),
                          capture_output=True, text=True)
    diag = (open(os.path.join(SCRATCH, "_aggregate", "check.err"), errors="ignore").read() +
            open(os.path.join(SCRATCH, "_aggregate", "check.out"), errors="ignore").read())
    first = next((l for l in diag.splitlines() if l.strip()), "")
    n = WIP_RE.search(diag)
    return first, (n.group(1) if n else "0"), os.path.relpath(agg, ROOT[0])


def compile_error(rel, diag, lines):
    """(bucket, detail) for a red that matches no declared-failure message.

    The owner is whichever file in the tree holds the offending source text at the
    offending line. If that is `rel` the defect is here; otherwise this file only
    IMPORTS the broken one, and reporting it as broken here would send a unit to fix the
    wrong file -- which is the specific failure this whole tool exists to prevent.

    The `>` gutter marks a CARET, so the marked line can be blank (an unterminated
    `def foo(` points at the line after it). An empty text identifies nothing -- every
    file with a blank line at that number matches -- so the search walks back to the
    nearest non-empty gutter line, and REFUSES to guess if there is none.
    """
    exp = " ".join(re.findall(r"^- (?:expected|observed) : (.*)$", diag, re.M))
    at = LOC_RE.search(diag)
    if not at:
        return "broken-here", "%s -- no Location block; %s" % (
            rel, exp or " ".join(diag.split())[:90])
    marked, text = int(at.group(1)), at.group(2).strip()
    gutter = [(int(n), t.strip()) for n, t in GUTTER_RE.findall(diag)]
    lineno, text = next(((n, t) for n, t in reversed(gutter) if t), (marked, text))
    if not text:
        return "broken-here", ("%s:%d  (blank line: owner NOT identifiable from the "
                               "diagnostic) -- expected %s" % (rel, marked, exp))
    homes = [p for p, ls in lines.items()
             if lineno <= len(ls) and ls[lineno - 1].strip() == text]
    hint = MODPATH_RE.search(diag)
    where = "%s:%d  %s" % (rel if rel in homes else ",".join(homes) or "UNKNOWN FILE",
                           lineno, text)
    if rel in homes:
        return "broken-here", "%s -- expected %s" % (where, exp)
    return "broken-in-import", "%s is the owner, imported here; observed names %s" % (
        where, hint.group(1) if hint else "(no module prefix)")


def classify(rec, lines):
    """Bucket by CAUSE. `broken-*` is the residual: every red that matches a declared
    failure message is named, and one that matches none is a real defect."""
    rel, rows, attempts, diag = rec
    first = next((l for l in diag.splitlines() if l.strip()), "")
    tried, distinct, voids = attempts

    if first == "ALL PROOFS CHECK":
        if rows:
            # bend disagreed with itself about the row count; say so on the line rather
            # than print a number that will not reproduce.
            return "green", "rows=%d%s%s" % (
                rows,
                "" if distinct == 1 else "  *** UNSTABLE: %d distinct counts ***" % distinct,
                "" if not voids else "  (%d void attempt(s))" % voids)
        origin = main_origin(rel)
        if origin is None:
            return "no-main", "library: no main anywhere in scope (%d attempts)" % tried
        return "no-rows", "a main IS in scope (%s); it printed 0 rows in %d attempts" % (
            origin, tried)

    if first == "SOME PROOFS FAIL":
        m = FOREIGN_RE.search(diag)
        if m:
            names = re.findall(r"^- (\S+)", diag, re.M)
            # An imported name is written `../dtype.Dt.bf16`; a declared one `Dt.bf16`.
            own = [x for x in names if "/" not in x]
            return "foreign-code-surface", "N=%s, %s: %s" % (
                m.group(1),
                ("declares %d own" % len(own)) if own
                else ("propagates %d imported" % len(names)),
                ", ".join((own or names)[:3]))
        if WIP_RE.search(diag) or WIP_TAIL_RE.search(diag):
            # A member of the proof set is judged by the SET. Judged alone it reports TODOs
            # that only mean "somewhere else in the set" -- PROOF.bend holds 16 of 34 and
            # LAWS.bend holds none, so per-file it reported 3 reds for a set that is clean.
            if _SET[0] and PROOF_MEMBER_RE.search(rel):
                if _SET[0] == "ALL PROOFS CHECK":
                    # NEVER "green" on 0 rows: that is the vacuous pass this tool exists to
                    # catch, and a proof file has no main, so it would print 0 forever.
                    if rows:
                        return "green", "rows=%d; proof SET clean via %s" % (rows, _SET[2])
                    origin = main_origin(rel)
                    return ("no-main" if origin is None else "no-rows"), (
                        "library: no main; proof SET clean via %s" % _SET[2] if origin is None
                        else "a main IS in scope (%s) but printed 0 rows; SET clean via %s"
                             % (origin, _SET[2]))
                return "proof-in-progress", "SET has %s TODO%s via %s (this file alone: %s)" % (
                    _SET[1], "" if _SET[1] == "1" else "s",
                    _SET[2], n.group(1) if (n := WIP_RE.search(diag)) else
                    "not-a-proof-yet")
            n = WIP_RE.search(diag)
            # The MESSAGE decides; the filename is corroboration only, and is reported
            # as a note so a reader can see it was not what entered the bucket.
            return "proof-in-progress", "N=%s TODOs, unfinished%s" % (
                n.group(1) if n else "?",
                " (law/PROOF file)" if re.search(r"(PROOF|LAWS)", rel) else "")
        return compile_error(rel, diag, lines)

    return "no-verdict", "no diagnostics in %d attempts (bend died?)" % tried


ROOT = [REPO]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("-P", type=int, default=12, help="parallel bend invocations")
    ap.add_argument("--attempts", type=int, default=6, help="max runs per file (agreement, not one run)")
    ap.add_argument("--only", default="", help="substring filter on the path")
    ap.add_argument("--root", default=REPO,
                    help="tree root; point it at a COPY to run a negative control")
    ap.add_argument("--json", action="store_true", help="machine-readable records")
    args = ap.parse_args()
    os.environ["ONE_ATTEMPTS"] = str(args.attempts)
    if not os.path.exists(ONE):
        sys.exit("missing %s -- tree-verdict.py refuses to guess a per-file checker" % ONE)
    ROOT[0] = os.path.abspath(args.root)

    files = [f for f in bend_files(ROOT[0]) if args.only in os.path.relpath(f, ROOT[0])]
    global lines_by_file
    lines_by_file = corpus(files)
    os.makedirs(SCRATCH, exist_ok=True)
    with cf.ThreadPoolExecutor(args.P) as pool:
        out = [(r, classify(r, lines_by_file)) for r in pool.map(check_one, files)]

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
