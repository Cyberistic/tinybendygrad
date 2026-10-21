#!/usr/bin/env python3
"""gates/pincensus-gate.py -- THE PIN CENSUS.

WHAT THIS IS. Five pin events landed in this tree in two days and EVERY ONE OF THEM IS
DESCRIBED IN A DIFFERENT PLACE. A re-vendor moved the pin and the old pin was kept as a
second row. A `.txt` to `.rows` rename moved a carve-out from 175 to 244 on both sides and
`AGENTS.md` recorded the old number for a week. An expected-file rename broke 86 witnesses.
An upstream `ParamArg` move was followed in 108 sites. `GROUP`/`FLIP` were deleted and 216
oracle rows changed shape. All five were found BY ACCIDENT -- a crash, a diff, a plant going
red -- and never by asking. This gate is the asking, and it is a CENSUS: it repairs nothing.

THE THREE KINDS OF WRONG, WHICH ARE THREE DIFFERENT POPULATIONS WITH THREE REMEDIES:

  1 CAN-FAIL     a pin a CODE file reads and compares against live state. Going stale makes
                 something red. THIS IS A REGRESSION ROW. The remedy is none.
  2 CANNOT-FAIL  a literal pin in code that NO code reads. It was true when written and can
                 be false forever. THIS IS THE `artefacts_ok()` CLASS. The remedy is an
                 instrument that reads it.
  3 PROSE-ONLY   a pin whose only copy is prose. It cannot even be re-derived, because
                 nothing else records it. The remedy is the one `checks/e2e.py` already
                 models for `BODY_SHA`: DECLARE WHAT KIND OF CLAIM IT IS, IN THE FILE.

AND CLASS 3's REMEDY HAS TWO HALVES, AND UNTIL BOTH WERE IN, THE FLAGSHIP PIN WAS UNMEASURABLE.
`checks/e2e.py` declared WHAT KIND of claim `BODY_SHA` is -- a content pin, not a behaviour
claim -- in prose, and the census could not use it: a pin with no SUBJECT is a literal, and
the row read NO-MEASUREMENT. So the file now also declares WHICH FILE the pin is about, in a
name a machine can read (`ORACLE_SUBJECT`, `BODY_SUBJECT`), and the census resolves it through
`gates/bind-subject.py`. The two halves are the same declaration: the first says what KIND of
claim it is, the second says what it is a claim ABOUT. A pin with the first and not the second
is prose wearing a pin's name.

THE VERDICT VOCABULARY IS `gates/gatekit.py`'s AND NOT INVENTED HERE:
  PASS 0 emitted and its accounting balances · FAIL 1 unused, a census judges nothing ·
  REFUSED 3 a precondition was absent or the population does not balance ·
  SKIP 4 nothing to measure · DEAD 5 it ran and emitted no rows.
`SKIP IS NOT PASS`, and so is a census that printed a table it could not account for.

A CENSUS IS NOT A GATE, AND THE DIFFERENCE IS THE EXIT CODE. Nothing here turns red because
a pin went stale; the third question below is the measurement of whether it COULD, and the
answer is reported rather than asserted.
"""
import argparse
import hashlib
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ART = os.path.join(HERE, "artifacts", "pincensus-gate")
PY = ".venv/bin/python"

PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5

# A value token: a content-addressed literal, carrying any revision SUFFIX the site wrote
# with it. The suffix is part of the pin -- `ad117c928^` is the PARENT of `ad117c928`, and a
# census that drops the caret reports a different object than the one the gate uses.
TOKEN = re.compile(r"\b([0-9a-f]{7,64})(~|\^|@{0,1}|\.\.)?\b")
SLOP = ".agents/slop"


def load_pop():
    """The discovery module, BY PATH -- `gates/docnum-census.py` is loaded this way by
    `gates/prose-census.py` (`load_owner`), and a hyphen is not an importable name."""
    spec = importlib.util.spec_from_file_location(
        "pincensus_pop", os.path.join(HERE, "pincensus-pop.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_bind():
    """The subject resolver, BY PATH, for the same reason `load_pop` is by path: a hyphen is
    not an importable name, and a second copy of the join rule would be a second witness."""
    spec = importlib.util.spec_from_file_location(
        "pincensus_bind", os.path.join(HERE, "bind-subject.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_pintable():
    """The EXPECTATION-ROW population's discovery module, BY PATH, for the same reason.

    **THE SECOND POPULATION, AND WHY IT IS A SEPARATE MODULE AND A SEPARATE TABLE.**
    `gates/pincensus-pop.py`'s value token is a CONTENT ADDRESS, and that is what makes a
    pin re-derivable: the census hashes the subject and compares two independent values. A
    PIN TABLE'S ROWS ARE EXPECTATIONS -- `checks/differ.py`'s `PINS` holds `"graphs": "34"`
    and `"stable-pairs": "5 of 5"` -- and an expectation cannot be re-derived by hashing
    anything, because the thing it is about is a RUN. So the flagship table of this tree
    was invisible to the instrument that exists to ask about pins, and the gap was known,
    named and unclosed.

    **THE DENOMINATOR IS NOT MERGED, AND THE REASON IS THE PRIOR UNIT'S.** The
    content-addressed rows and the expectation rows are DIFFERENT OBJECTS -- an address and
    an expectation -- so they are counted apart: `rows` keeps its meaning and its number
    exactly as it was, and the expectation rows get their own count, their own classes and
    their own table. The prior unit wrote that it would "rather report the gap than widen
    the rule and quietly change what the number means", and this is the same refusal with
    the gap CLOSED: the gap is closed by a second, named, separately-denominated
    population, not by redefinition.
    """
    spec = importlib.util.spec_from_file_location(
        "pintable_pop", os.path.join(HERE, "pintable-pop.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_pintable_gate():
    """The gate that already names a pin table's artifact, BY PATH.

    `PINS` matches no `_ARTIFACT` prefix, so the binding join cannot see it.
    The subject is not a handwritten exception for `checks/differ.py`. It is
    the artifact `artifact_of` reads out of the one file `classify` says
    pintable executes. A second copy of that rule would be a second witness.
    """
    spec = importlib.util.spec_from_file_location(
        "pintable_gate", os.path.join(HERE, "pintable-gate.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def git(git_root, *argv):
    r = subprocess.run(["git", *argv], cwd=git_root, capture_output=True, text=True)
    return (r.stdout if r.returncode == 0 else "").strip()


def sha256_of(path):
    try:
        with open(path, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except OSError:
        return None


# WHERE A PIN'S SUBJECT IS LOOKED FOR, AND WHY THIS LIST IS NOT A HAND LIST.
# `gates/gatekit.py:330` is the tree's OWN resolution -- `root / rel`, repo-root-relative --
# and `checks/substrate.py` uses the same. The first draft of this census hard-coded
# `.agents/slop/` for every digest and therefore answered SUBJECT-ABSENT for 19 pins whose
# subjects sit at the repo root, in `tinygrad/` and `gates/oracles/`. A wrong reason is worse
# than no reason, so the order is: the tree's own rule first, then the one place that differs,
# then STOP and say where it looked.
SUBJECT_ROOTS = (".", ".agents/slop")
# Never read a running artifact: `checks/differ.py repro` was live at pids 14253/14303 when
# this census was taken, and `runs/` holds its output. A pin whose subject is there is REPORTED
# as living in a gitignored run directory, not resolved against it.
NEVER_READ = ("runs/",)


def currency(value, git_root, subject, corpus_root=None):
    """-> (shape, verdict, detail) for ONE value token. Every branch is a MEASUREMENT and
    every refusal NAMES what it tried, because this census's first draft asserted
    SUBJECT-ABSENT for nineteen subjects that were present at the repo root.

    Three shapes, and they are not equally decidable, so the census says which is which rather
    than letting one column cover all of them:

      REVISION  `git cat-file -t <rev>` answers whether it resolves -- a fact about the object
                store, not about the prose. `rev-list --count <rev>..HEAD` answers how far
                HEAD has moved past it, which is the question a re-vendor makes urgent.
      DIGEST    a sha256 the site names a subject for. Re-derivable: hash the subject, compare.
                A TRUNCATED digest is compared as a prefix and labelled PREFIX, because
                `gates/mixin-op-gate.py:68` holds 12-hex values and calling those DANGLING
                revisions was wrong -- they are sha256 prefixes.
      UNNAMED   no subject, no derivation, nothing to recompute. That is not a gap in this
                file: it is the finding. The dict, or the prose, is the only copy.

    `subject` is a DICT and not a path, because a subject has two shapes and the difference
    is the difference between a measurement and a refusal: a FILE the census may hash, and a
    RUN ARTIFACT it must not (a run may be LIVE, and a live artifact read under a pin is the
    "STALE FILE WAS SERVING AS THE WITNESS" defect).

    `corpus_root` IS WHERE THE SUBJECT IS LOOKED FOR FIRST. The census reads its corpus from
    one root and its git objects from another, and a subject read from the WRONG one would
    measure a file that is not the corpus's: a plant that moves the subject in a copy would
    then be measuring the copy of the pin against the ORIGINAL of the subject, and could not
    fail. The git root is the FALLBACK, so the existing plant -- which copies the pin's file
    and lets the subject be read from the real tree -- still reads the same verdict.
    """
    bare, suffix = value
    kind = git(git_root, "cat-file", "-t", bare + (suffix or "")) if git_root else ""
    if kind in ("commit", "tag"):
        behind = git(git_root, "rev-list", "--count", f"{bare}{suffix or ''}..HEAD")
        return "REVISION", "RESOLVES", f"cat-file -t={kind}; behind-HEAD={behind or '?'}"
    if subject:
        return digest_currency(bare, git_root, subject, corpus_root)
    if 7 <= len(bare) <= 64:
        return "OTHER", "NO-MEASUREMENT", \
            f"len={len(bare)}, not a revision in this object store and no subject named"
    return "OTHER", "NO-MEASUREMENT", f"len={len(bare)}, not a revision length"


def subject_of(resolved, key, decl):
    """-> the subject of ONE value, or None. THE PRECEDENCE IS FIXED, AND IT IS THE POINT.

      1 A `_SUBJECT` declaration names the FILE the pin is about. It wins over everything,
        because it is the tree's own statement of the subject and it is a NAME, not an
        inference this file made.
      2 An `_ARTIFACT` declaration names the file a pin TABLE'S ROWS are carried by. It
        applies only to a value that came from a DICT KEY, because a row name is what an
        artifact carries; a bare literal has no row.
      3 Otherwise the dict key IS the subject, which is the original behaviour and the one
        `checks/differ.py`'s `ORACLE_PIN` depends on.

    A subject of None is the honest answer when the binding names none: a digest with no
    subject is a literal, and the census says so rather than inventing a path.
    """
    if resolved is None:
        return {"kind": "file", "path": key} if key else None
    if resolved["kind"] == "SUBJECT":
        return {"kind": "file", "path": resolved["value"], "at": resolved["at"]}
    if key is None:
        return None
    dirs = decl["run-dirs"]
    return {"kind": "run-artifact", "artifact": resolved["value"],
            "dir": dirs[0] if dirs else "", "row": key, "at": resolved["at"]}


def digest_currency(bare, git_root, subject, corpus_root=None):
    """-> (shape, verdict, detail) for a DIGEST whose subject is named.

    THE TWO SUBJECT SHAPES, AND THE SECOND ONE IS NOT READ.

      a FILE         the census hashes it and compares. The pin is the LITERAL in the source
                     and the subject is a BYTE STRING on disk, so the comparison is between two
                     INDEPENDENT values: a subject that moved without the pin moving is
                     MISMATCH, which is a RED, which is the whole point of naming it.
      a RUN ARTIFACT the subject is under `runs/`, which is GITIGNORED BY DESIGN. The census
                     says where it is and refuses to read it, because a run may be live. The
                     verdict is NOT "missing": the artifact is missing from the tree BY
                     DESIGN, and reporting that as a missing subject is a false claim about a
                     tree that is behaving correctly.
    """
    if subject["kind"] == "run-artifact":
        rel = os.path.normpath(os.path.join(subject["dir"], subject["artifact"])) \
            if subject["dir"] else subject["artifact"]
        at = subject.get("at") or "-"
        return "DIGEST", "SUBJECT-IN-GITIGNORED-RUNS", \
            (f"the row '{subject['row']}' is carried by {rel} (declared at {at}); a run "
             f"artifact is gitignored by design and its bytes are not read, so this digest is "
             f"not re-derivable here and its absence is not a defect")
    roots = []
    for root, label in ((corpus_root, "corpus"), (git_root, "git")):
        if root and root not in [r for r, _ in roots]:
            roots.append((root, label))
    for base in SUBJECT_ROOTS:
        rel = os.path.normpath(os.path.join(base, subject["path"]))
        if any(rel.startswith(n) for n in NEVER_READ):
            return "DIGEST", "SUBJECT-IN-GITIGNORED-RUNS", \
                f"{rel} is under a gitignored run directory; not read"
        for root, label in roots:
            got = sha256_of(os.path.join(root, rel))
            if got is not None:
                how = "PREFIX " if len(bare) < 64 else ""
                ok = got.startswith(bare)
                return "DIGEST", ("%s%s" % (how, "CURRENT" if ok else "MISMATCH")), \
                    f"sha256({rel})[{label}]={got[:16]} vs pinned {bare[:16]}"
    return "DIGEST", "SUBJECT-NOT-FOUND", \
        f"looked in {', '.join(SUBJECT_ROOTS)} for {subject['path']}; found neither"


def vendored(git_root):
    """-> {path} for every tracked file that is BYTE-IDENTICAL to `refs/remotes/upstream/master`.

    READ AGAINST THE REF AND NOT FETCHED: other units are live in this tree and `git fetch`
    moves a ref under them. A vendored file's pins are UPSTREAM'S -- `examples/mlperf`'s three
    weight digests are a fact about a model zoo, not about this port -- so they are counted and
    REPORTED SEPARATELY rather than silently folded into the port's pin population.

    This is a per-FILE flag with a blob comparison, not a list of directories. The directory
    reading would be wrong and the command shows it: `tinygrad/` and `test/` and `docs/` are
    wholly upstream (230/230, 390/390, 34/34 against `git ls-tree -r refs/remotes/upstream/master`),
    while `examples/` is 265 upstream against 271 ours and `extra/` is 721 against 703, so a
    directory either hides our six or claims upstream's 18.
    """
    up = {}
    for line in git(git_root, "ls-tree", "-r", "refs/remotes/upstream/master").splitlines():
        parts = line.split()
        if len(parts) >= 3:
            up[parts[3]] = parts[2]
    ours = {}
    for line in git(git_root, "ls-tree", "-r", "HEAD").splitlines():
        parts = line.split()
        if len(parts) >= 3:
            ours[parts[3]] = parts[2]
    return {p for p, b in ours.items() if up.get(p) == b}


def census(root=ROOT, git_root=ROOT, scratch=False):
    """-> (rows, meta). THE WHOLE CENSUS. Pure in the corpus's bytes: `root` is read,
    `git_root` is asked, so a plant can serve a mutated corpus and the same tree."""
    P = load_pop()
    B = load_bind()
    if scratch:
        # A PLANT'S ROOT IS NOT A GIT REPO, so the walk is bounded by what the scratch root
        # HOLDS rather than by the tree. Stated because a bound that changes with the caller
        # is a bound a reader has to check.
        files = {}
        for dp, dn, fns in os.walk(root):
            dn[:] = [d for d in dn if d != ".git"]
            for fn in fns:
                p = os.path.join(dp, fn)
                try:
                    files[os.path.relpath(p, root)] = open(p, "rb").read().decode("utf-8")
                except (OSError, UnicodeDecodeError):
                    continue
        corpus = files
        counts = {"walk-decoded": len(files), "tree-tracked": "n/a (scratch root)"}
        host = {t: P.host_of(v) for t, v in corpus.items()}
    else:
        loaded = P.load(root)
        corpus, counts = loaded["corpus"], loaded["counts"]
        host = P.hosts(corpus)

    code = {t: P.code_lines(corpus[t], host[t]) for t in corpus if host[t] != "prose"}
    twins = P.twins(corpus) if not scratch else {}

    sites = P.rule_a(corpus, host)
    prose_lines = P.rule_b(corpus, host)
    upstream = set() if scratch else vendored(git_root)

    # WHAT EACH PIN IS ABOUT. The declarations are discovered from the corpus's own CODE, so a
    # subject is a NAME the tree already states rather than a path this file carries.
    decls = B.declarations(corpus, code)
    empty = {"subjects": {}, "artifacts": {}, "run-dirs": [], "at": {}}

    # The values any CODE site carries, so a prose line can be scored as a shadow or as the
    # only copy. This is what separates class 3 from class 2's prose cousins.
    code_values = {v for s in sites if s["host"] != "prose" for v in s["values"]}

    rows = []
    for s in sites:
        read = P.readers(s["name"], code, (s["file"], s["line"], s["end"])) \
            if s["host"] != "prose" else []
        if s["host"] == "prose":
            kind = ("PROSE-SHADOW" if any(v in code_values for v in s["values"])
                    else "PROSE-ONLY")
        else:
            kind = "CAN-FAIL" if read else "CANNOT-FAIL"
        pairs = s.get("pairs") or {}
        decl = decls.get(s["file"], empty)
        resolved = B.resolve(s["name"], decl) if s["host"] != "prose" else None
        for i, raw in enumerate(TOKEN.finditer(" ".join(s["values"]))):
            value = (raw.group(1), raw.group(2))
            if s["host"] != "prose" and i >= len(s["values"]):
                break
            key = next((k for k, v in pairs.items() if v == value[0]), None)
            subject = subject_of(resolved, key, decl)
            shape, verdict, detail = currency(value, git_root, subject, root)
            rows.append({
                "class": kind, "what": s["name"], "where": f'{s["file"]}:{s["line"]}',
                "host": s["host"], "literal-or-derivation": "literal",
                "value": value[0] + (value[1] or ""), "shape": shape,
                "currency": verdict, "detail": detail,
                "readers": ";".join(f"{t}:{i}" for t, i in read[:3]) or "-",
                "n-readers": len(read),
                "origin": "UPSTREAM" if s["file"] in upstream else "OURS",
            })
        if not TOKEN.search(" ".join(s["values"])):
            rows.append({
                "class": kind, "what": s["name"], "where": f'{s["file"]}:{s["line"]}',
                "host": s["host"], "literal-or-derivation": "literal",
                "value": ",".join(s["values"])[:40], "shape": "OTHER",
                "currency": "NO-MEASUREMENT", "detail": "no revision-shaped token",
                "readers": ";".join(f"{t}:{i}" for t, i in read[:3]) or "-",
                "n-readers": len(read),
                "origin": "UPSTREAM" if s["file"] in upstream else "OURS"})

    for pl in prose_lines:
        raw = TOKEN.search(pl["text"])
        if not raw:
            continue
        rows.append({
            "class": ("PROSE-SHADOW" if raw.group(1) in code_values else "PROSE-ONLY"),
            "what": "prose-line", "where": f'{pl["file"]}:{pl["line"]}',
            "host": "prose", "literal-or-derivation": "literal",
            "value": raw.group(1) + (raw.group(2) or ""), "shape": "PROSE",
            "currency": "NO-MEASUREMENT",
            "detail": "prose is the only copy; no command is named on the line",
            "readers": "-", "n-readers": 0,
            "origin": "UPSTREAM" if pl["file"] in upstream else "OURS",
            "text": pl["text"][:100]})

    meta = {
        "counts": counts,
        "hosts": P.host_census(corpus, host) if not scratch else {},
        "sites": len(sites), "prose-lines": len(prose_lines),
        "twins-over-1": len([t for t, v in twins.items() if len(v) > 1]),
        "rows": len(rows),
        "classes": dict(Counter(r["class"] for r in rows)),
        "origin": dict(Counter(r["origin"] for r in rows)),
        "currency": dict(Counter(r["currency"] for r in rows)),
        "root": root, "git_root": git_root,
    }
    # THE SECOND POPULATION, COUNTED APART. `meta["rows"]` above is UNCHANGED by it and
    # MEANS WHAT IT MEANT: the content-addressed pin values the census decided about. The
    # expectation rows are a different object -- an address is re-derivable, an expectation
    # is only comparable -- and they are counted apart, with their own classes, their own
    # currency vocabulary and their own table.
    #
    # **THE ARITY OF `census()` IS UNCHANGED**, because `gates/pincensus-plant.py` calls it
    # as `rows, meta = census(...)` and that file is not this file's to edit.
    exrows, exmeta = expectation_census(corpus, host, code, decls, git_root, root, upstream, P,
                                        load_pintable(), B)
    meta["expectations"] = exmeta
    meta["expectation-rows"] = exrows
    return rows, meta


# THE EXPECTATION POPULATION, AND ITS THREE MOVES.
#
# 1 THE JOIN. An expectation row's KEY IS A ROW NAME, not a path. `gates/bind-subject.py`
#   already says so -- "a row name is what an artifact carries; a bare literal has no row"
#   -- and `subject_of()` above already implements it: with an `_ARTIFACT` declaration the
#   key names a row of THAT artifact, without one the key would be read as a path. The
#   expectation rows therefore use the SAME join and only change WHICH key they ask about:
#   a key of a table with no `_ARTIFACT` declaration names NOTHING, and the honest answer
#   to that is a refusal that says so, not a search for a file called `graphs`.
#
# 2 THE SUBJECT'S TWO SHAPES. An `_ARTIFACT` declaration names a RUN artifact, and a run
#   artifact's bytes are not read here (a run may be LIVE); an `_SUBJECT` declaration names
#   a FILE, and a file can be read -- and an expectation IS comparable, by looking the key
#   up in the file's own `key=value` rows.
#
# 3 THE DECLARATION. The population is the tree's OWN declaration, read by path, because a
#   table can be patched after it is declared and then the literal and the live value
#   differ. The scan and the declaration are compared, and a disagreement is REPORTED.
#
# THE VERDICT VOCABULARY OF THIS POPULATION, AND IT IS THE CENSUS'S OWN:
#   CURRENT / MISMATCH / ROW-ABSENT   the subject was read and the row was compared
#   SUBJECT-IN-GITIGNORED-RUNS         the subject is a run artifact, so it is not read.
#                                     NOT CURRENT: this census does not compare the row
#                                     to a live run. That comparison is pintable-gate's.
#   NO-SUBJECT-DECLARED               the table's artifact is not named in a form a
#                                     machine can read -- a REFUSAL, and the finding.
#                                     The file pintable executes is not this class: its
#                                     subject is the artifact that file's reader names.
#                                     A copy that is not that file stays here unless its
#                                     own binding resolves.
#   NOT-CARRIED                       the scan and the tree's declaration disagree
def expectation_subject(resolved, decl, key):
    """-> the subject a `_SUBJECT` or `_ARTIFACT` binding names, or None.

    None means the binding join names nothing. It does not mean the row has no
    subject. `PINS` matches no `_ARTIFACT` prefix, so this function returns None
    for it. Which file pintable executes is not knowable here: a caller that
    wants only the binding still sees None, and `expectation_census` asks.
    """
    if resolved is None:
        return None
    if resolved["kind"] == "SUBJECT":
        return {"kind": "file", "path": resolved["value"], "at": resolved["at"]}
    dirs = decl["run-dirs"]
    return {"kind": "run-artifact", "artifact": resolved["value"],
            "dir": dirs[0] if dirs else "", "row": key, "at": resolved["at"]}


def expectation_currency(value, subject, corpus_root, git_root):
    """-> (verdict, detail) for ONE expectation row, by COMPARING it with its subject.

    An expectation is COMPARABLE and not RE-DERIVABLE: the row must read exactly the value
    the tree declared, and the subject is read to find out. The two values are INDEPENDENT
    -- one is the literal in the source, the other is the bytes on disk -- so the comparison
    can fail, which is what a pin is for.
    """
    if subject is None:
        return "NO-SUBJECT-DECLARED", (
            "the table names no artifact, so the row's subject cannot be located; the key "
            "names a ROW of an artifact, not a path, and no `_ARTIFACT` declaration names "
            "the artifact")
    if subject["kind"] == "run-artifact":
        rel = os.path.normpath(os.path.join(subject["dir"], subject["artifact"])) \
            if subject["dir"] else subject["artifact"]
        return "SUBJECT-IN-GITIGNORED-RUNS", (
            f"the row '{subject['row']}' is carried by {rel} (declared at {subject['at']}); a "
            f"run artifact is gitignored by design and its bytes are not read, so this "
            f"expectation is not comparable here and its absence is not a defect")
    for root, label in ((corpus_root, "corpus"), (git_root, "git")):
        if not root:
            continue
        for base in SUBJECT_ROOTS:
            rel = os.path.normpath(os.path.join(base, subject["path"]))
            if any(rel.startswith(n) for n in NEVER_READ):
                return "SUBJECT-IN-GITIGNORED-RUNS", f"{rel} is under a gitignored run directory; not read"
            path = os.path.join(root, rel)
            if not os.path.isfile(path):
                continue
            got = None
            with open(path, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if "=" not in line:
                        continue
                    k, v = line.split("=", 1)
                    if k.strip() == subject.get("row", ""):
                        got = v.strip()
            if got is None:
                return "ROW-ABSENT", f"{rel} carries no row named '{subject.get('row', '')}'"
            return ("CURRENT" if got == value else "MISMATCH"), \
                f"{rel}[{subject.get('row', '')}]={got!r} vs expected {value!r}"
    return "SUBJECT-NOT-FOUND", \
        f"looked in {', '.join(SUBJECT_ROOTS)} for {subject['path']}; found neither"


def drop_addresses(pairs, hex_re):
    """-> pairs whose value is an expectation, not a content address.

    `pincensus-pop.HEX` is the hex-pin token. A row that matches it is already in the
    hex-pin population. Counting it here folds the two denominators. Measured before
    this filter: `REPRO_PINS["d10-transcript"]` (a sha256 at `checks/differ.py:339`) was
    both a hex pin and an expectation row.
    """
    return [(k, v) for k, v in pairs if not hex_re.search(v)]


def executed_files(exps, gate):
    """-> {table name: path} for the one file pintable executes.

    `pintable-gate.classify`, loaded by path, not a list of paths. A shadow's
    path ends in `/<authored path>`. A copy is not that file. Zero or many is
    not a subject: this function does not pick.
    """
    by_name = {}
    for e in exps:
        by_name.setdefault(e["name"], set()).add(e["file"])
    out = {}
    for name, files in by_name.items():
        flag, _, _ = gate.classify(sorted(files))
        if len(flag) == 1:
            out[name] = flag[0]
    return out


def subject_executed(rel_file, name, text, decl, bind, key, gate):
    """-> the run artifact the executed file's reader names, or None.

    Not an `_ARTIFACT` binding. `artifact_of` is the module's own declaration of
    which file the table's rows are carried by, and only for the file pintable
    executes. The path is a run artifact. This census does not read it and does
    not call the row CURRENT. A path that is not under `runs/` is not used: reading
    it to compare would be pintable-gate's claim, not this one.
    """
    found, how = gate.artifact_of(name, text, decl, bind)
    if not found or not any(found.startswith(n) for n in NEVER_READ):
        return None
    return {"kind": "run-artifact", "artifact": found, "dir": "", "row": key,
            "at": "%s, the file pintable executes; %s" % (rel_file, how)}


def expectation_census(corpus, host, code, decls, git_root, corpus_root, upstream, P, T, B):
    """-> (rows, meta). THE SECOND POPULATION: the rows of a PIN TABLE whose value is an
    EXPECTATION rather than a content address.

    **THE POPULATION IS THE TREE'S OWN DECLARATION, AND THE SCAN IS THE CROSS-CHECK.** For
    every table the census reads the module's attribute BY PATH -- executing the defining
    module, as `gates/corpusverdict-gate.py` already does with `checks/differ.py` -- and
    compares it against what `ast` sees in the source. The two are independent readings, so
    they can disagree, and when they do the census carries the DECLARATION (what the tree
    will actually compare) and says that the scan and the tree disagree.

    **THE FLAGSHIP SUBJECT IS THE FILE PINTABLE EXECUTES, NOT A PATH EXCEPTION.** A table
    with no `_ARTIFACT` binding is `NO-SUBJECT-DECLARED` except on that one file. The
    artifact is the one `pintable-gate.artifact_of` already names. It is a run artifact,
    so the class is `SUBJECT-IN-GITIGNORED-RUNS`. It is not `CURRENT`.
    """
    binds = T.bindings(corpus, host)
    tabs = T.tables(binds, P.PIN_NAME)
    exps = T.expectations(tabs, P.HEX)
    # THE TABLE each row belongs to, so a table's cross-check is computed ONCE and not per row.
    by_table = {(t["file"], t["line"], t["name"]): t for t in tabs}
    gate = load_pintable_gate()
    executed = executed_files(exps, gate)

    rows, meta = [], {"tables": 0, "cross-checked": 0, "not-cross-checkable": 0, "disagreeing": 0,
                      "tables-not-carried": 0, "declaring-files": set()}
    for (f, line, name), tab in sorted(by_table.items()):
        if not any(e["file"] == f and e["name"] == name for e in exps):
            continue
        meta["tables"] += 1
        decl_rows, note = T.declaration(corpus_root, f, name)
        # HEX-VALUED ROWS ARE THE OTHER POPULATION. Compared and emitted only after they
        # are dropped, so a mixed table (`REPRO_PINS` holds `rc=0` and a sha256) cannot
        # put its content address in this count.
        scan_rows = dict(drop_addresses(tab["rows"], P.HEX))
        if decl_rows is None:
            meta["not-cross-checkable"] += 1
            carried, source = list(scan_rows.items()), "literal"
            cross = f"NOT CROSS-CHECKABLE: {note}"
        else:
            meta["cross-checked"] += 1
            meta["declaring-files"].add(f)
            decl = dict(drop_addresses(decl_rows, P.HEX))
            carried, source = list(decl.items()), "declaration"
            diff = [k for k in set(scan_rows) | set(decl) if scan_rows.get(k) != decl.get(k)]
            if diff:
                meta["disagreeing"] += 1
                cross = ("THE SCAN AND THE TREE DISAGREE on " + ", ".join(sorted(diff)))
            else:
                cross = "the scan and the tree's own declaration agree"
            if tab["rebindings"]:
                meta["tables-not-carried"] += 1
                cross += f"; the name is bound {len(tab['rebindings'])} more time(s)"

        decl_for_file = decls.get(f, {"subjects": {}, "artifacts": {}, "run-dirs": [], "at": {}})
        resolved = B.resolve(name, decl_for_file)
        read = P.readers(name, code, (f, line, line)) if code else []
        for key, value in carried:
            subject = expectation_subject(resolved, decl_for_file, key)
            # A binding wins. Only the file pintable executes, and only when the
            # binding names nothing, takes the reader scan. A copy stays unbound.
            if subject is None and executed.get(name) == f:
                subject = subject_executed(
                    f, name, corpus.get(f, ""), decl_for_file, B, key, gate)
            verdict, detail = expectation_currency(value, subject, corpus_root, git_root)
            rows.append({
                "class": "CAN-FAIL" if read else "CANNOT-FAIL",
                "what": f"{name}[{key}]", "where": f"{f}:{line}",
                "host": "python", "literal-or-derivation": source,
                "value": value, "shape": "EXPECTATION",
                "currency": verdict,
                "detail": f"{detail}; {cross}",
                "readers": ";".join(f"{t}:{i}" for t, i in read[:3]) or "-",
                "n-readers": len(read),
                "origin": "UPSTREAM" if f in upstream else "OURS",
            })
    meta["declaring-files"] = sorted(meta["declaring-files"])
    meta["classes"] = dict(Counter(r["class"] for r in rows))
    meta["currency"] = dict(Counter(r["currency"] for r in rows))
    meta["origin"] = dict(Counter(r["origin"] for r in rows))
    meta["rows"] = len(rows)
    return rows, meta


COLUMNS = ["class", "origin", "what", "where", "host", "literal-or-derivation", "value",
           "shape", "currency", "n-readers", "readers", "detail"]


def write_rows(rows, meta):
    os.makedirs(ART, exist_ok=True)
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    with open(os.path.join(ART, "census.rows"), "w") as fh:
        fh.write("# pincensus census.rows -- TAB separated. Generated; the generator is "
                 "gates/pincensus-gate.py.\n")
        fh.write(f"# written {stamp} HEAD={git(meta['git_root'], 'rev-parse', '--short', 'HEAD')}\n")
        fh.write("\t".join(COLUMNS) + "\n")
        for r in rows:
            fh.write("\t".join(str(r.get(c, "")).replace("\t", " ") for c in COLUMNS) + "\n")
    return stamp


def write_expectation_rows(rows, meta):
    """The SECOND TABLE, AND IT IS A SEPARATE FILE FOR THE SAME REASON THE COUNT IS SEPARATE.

    `census.rows` is the content-addressed population and its header says so. A reader who
    finds 597 rows in ONE file cannot tell which kind a row is, and a row count that mixes
    two denominators is a number nobody can check."""
    os.makedirs(ART, exist_ok=True)
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    with open(os.path.join(ART, "census-tables.rows"), "w") as fh:
        fh.write("# pincensus census-tables.rows -- TAB separated. Generated; the generator is "
                 "gates/pincensus-gate.py. THE EXPECTATION POPULATION: the rows of a PIN "
                 "TABLE whose value is an EXPECTATION and not a content address.\n")
        fh.write(f"# written {stamp} HEAD={git(meta['git_root'], 'rev-parse', '--short', 'HEAD')}\n")
        fh.write("\t".join(COLUMNS) + "\n")
        for r in rows:
            fh.write("\t".join(str(r.get(c, "")).replace("\t", " ") for c in COLUMNS) + "\n")
    return stamp


def reachability():
    """THE THIRD QUESTION. `DOES A PIN THAT GOES STALE MAKE ANYTHING GO RED BY ITSELF?`

    Measured from a FRESH CLONE's point of view, because that is the only point of view
    that can be reproduced by anyone else. Four probes, each a command, each printed.
    """
    hooks = [f for f in os.listdir(os.path.join(ROOT, ".git", "hooks"))
             if not f.endswith(".sample")] if os.path.isdir(os.path.join(ROOT, ".git", "hooks")) else []
    hooks_path = git(ROOT, "config", "--get", "core.hooksPath")
    wf = os.path.join(ROOT, ".github", "workflows")
    workflows = sorted(os.listdir(wf)) if os.path.isdir(wf) else []
    naming = []
    for w in workflows:
        try:
            body = open(os.path.join(wf, w), encoding="utf-8").read()
        except OSError:
            continue
        if re.search(r"\b(?:gates|checks)/[A-Za-z0-9_.-]+\.py\b", body):
            naming.append(w)
    art_tracked = len(git(ROOT, "ls-tree", "-r", "HEAD", "--name-only", "--",
                          "gates/artifacts").split())
    return {
        "git-hooks-non-sample": len(hooks), "git-hooks-named": hooks[:5],
        "core.hooksPath": hooks_path or "UNSET",
        "workflows": len(workflows), "workflows-naming-a-gate": naming,
        "gates-artifacts-tracked": art_tracked,
    }


# THE PLANT'S CORPUS, AND WHY IT IS SYNTHETIC. The live tree's scan and declaration
# AGREE (measured disagreeing=0), so a plant that waits for the tree to already be wrong
# cannot fail on the defect it exists to catch. The shape is the live leak: one table
# holding an expectation and a content address, which is `REPRO_PINS`.
_PLANT_DIGEST = "ab" * 32
_PLANT_SCALAR = "0123456789abcdef"
_PLANT_SCAN = "34"
_PLANT_DECLARED = "PLANTED"
_PLANT_BODY = (
    'HEX_PIN = "%s"\n'
    "PINS = {\n"
    '    "graphs": "%s",\n'
    '    "digest": "%s",\n'
    "}\n"
) % (_PLANT_SCALAR, _PLANT_SCAN, _PLANT_DIGEST)
_PLANT_REBIND = 'PINS["graphs"] = "%s"\n' % _PLANT_DECLARED


def _values(rows):
    return {r["value"] for r in rows}


def _one(rows, value):
    got = [r for r in rows if r.get("value") == value]
    return got[0] if len(got) == 1 else None


_SUBJECT_HEX = "cd" * 32
_SUBJECT_EXPECT = "34"
_SUBJECT_READER = (
    'D = "runs/planted/D"\n'
    "PINS = {\n"
    '    "graphs": "%s",\n'
    '    "digest": "%s",\n'
    "}\n"
    "def unhealthy():\n"
    '    path = D / "D0-run-summary.txt"\n'
    "    return PINS\n"
) % (_SUBJECT_EXPECT, _SUBJECT_HEX)
_SUBJECT_BARE = (
    'D = "runs/planted/D"\n'
    "PINS = {\n"
    '    "graphs": "%s",\n'
    '    "digest": "%s",\n'
    "}\n"
) % (_SUBJECT_EXPECT, _SUBJECT_HEX)
_BOUND_COPY = (
    'REPRO_ARTIFACT = "D0-repro.txt"\n'
    'D = "runs/planted/D"\n'
    "REPRO_PINS = {\n"
    '    "repro-rc": "rc=0",\n'
    "}\n"
)
_FLAG = "flag.py"
_COPY = "kept/flag.py"
_ORPHAN = "orphan.py"
_BOUND = "bound.py"
_BOUND_COPY_REL = "kept/bound.py"


def _place(dest, rel, text):
    path = os.path.join(dest, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def _at(rows, rel, value):
    got = [r for r in rows if r["where"].startswith(rel + ":") and r["value"] == value]
    return got[0] if len(got) == 1 else None


def plant_subject():
    """Attack copies. The live tree is opened for nothing and never written.

    The flagship is the file pintable executes, discovered by path, not named.
    A copy of that file with `PINS` and no artifact binding stays
    `NO-SUBJECT-DECLARED`. A copy that carries its own binding does not. A hex
    pin is not an expectation row. `meta["rows"]` does not move when the
    flagship subject is discovered. The discovered class is not `CURRENT`.
    """
    base = tempfile.mkdtemp(prefix="pincensus-subject-plant-")
    try:
        bare, read, bound = (os.path.join(base, n) for n in ("bare", "read", "bound"))
        for dest, body in ((bare, _SUBJECT_BARE), (read, _SUBJECT_READER)):
            for rel in (_FLAG, _COPY, _ORPHAN):
                _place(dest, rel, body)
        for rel in (_BOUND, _BOUND_COPY_REL):
            _place(bound, rel, _BOUND_COPY)
        b_rows, b_meta = census(bare, ROOT, scratch=True)
        r_rows, r_meta = census(read, ROOT, scratch=True)
        k_rows, k_meta = census(bound, ROOT, scratch=True)
        b_ex, r_ex = b_meta["expectation-rows"], r_meta["expectation-rows"]
        flag = _at(r_ex, _FLAG, _SUBJECT_EXPECT)
        copy = _at(r_ex, _COPY, _SUBJECT_EXPECT)
        orphan = _at(r_ex, _ORPHAN, _SUBJECT_EXPECT)
        bare_flag = _at(b_ex, _FLAG, _SUBJECT_EXPECT)
        bound_copy = _at(k_meta["expectation-rows"], _BOUND_COPY_REL, "rc=0")
        bad = []
        if flag is None or copy is None or orphan is None or bare_flag is None or bound_copy is None:
            bad.append("a side produced no expectation row, so the plant compared nothing")
        if flag is not None and flag["currency"] == "NO-SUBJECT-DECLARED":
            bad.append("the flagship table is NO-SUBJECT-DECLARED")
        if flag is not None and flag["currency"] == "CURRENT":
            bad.append("the flagship was classed CURRENT; currency is not this census's claim")
        if flag is not None and flag["currency"] != "SUBJECT-IN-GITIGNORED-RUNS":
            bad.append("the flagship subject was read or not a run artifact (%s)" % flag["currency"])
        if flag is not None and "pintable executes" not in flag["detail"]:
            bad.append("the flagship subject was not said to be the file pintable executes")
        if copy is not None and copy["currency"] != "NO-SUBJECT-DECLARED":
            bad.append("a copy with PINS and no artifact binding left NO-SUBJECT-DECLARED")
        if orphan is not None and orphan["currency"] != "NO-SUBJECT-DECLARED":
            bad.append("a file pintable does not execute was given the flagship subject")
        if bare_flag is not None and bare_flag["currency"] != "NO-SUBJECT-DECLARED":
            bad.append("a flagship with no reader was given a subject")
        if bound_copy is not None and bound_copy["currency"] == "NO-SUBJECT-DECLARED":
            bad.append("a copy that carries its own binding stayed NO-SUBJECT-DECLARED")
        if _SUBJECT_HEX not in _values(r_rows) or _SUBJECT_HEX in _values(r_ex):
            bad.append("a hex pin was not kept out of the expectation rows")
        if _SUBJECT_EXPECT in _values(r_rows):
            bad.append("an expectation row was counted as a hex pin")
        if b_meta["rows"] != r_meta["rows"]:
            bad.append("meta['rows'] moved when the flagship subject was discovered "
                       "(%s -> %s)" % (b_meta["rows"], r_meta["rows"]))
        if r_meta["rows"] != len(r_rows) or b_meta["rows"] != len(b_rows):
            bad.append("meta['rows'] does not mean the hex-pin rows")
        if any(r.get("shape") == "EXPECTATION" for r in r_rows):
            bad.append("a hex-pin row was shaped as an expectation")
        print("pincensus-gate --plant: flagship subject, on copies")
        print("  BARE     flagship=%s meta[rows]=%s" % (
            None if bare_flag is None else bare_flag["currency"], b_meta["rows"]))
        print("  READ     flagship=%s copy=%s orphan=%s meta[rows]=%s" % (
            None if flag is None else flag["currency"],
            None if copy is None else copy["currency"],
            None if orphan is None else orphan["currency"], r_meta["rows"]))
        print("  BOUND    copy=%s" % (None if bound_copy is None else bound_copy["currency"]))
        if bad:
            print("pincensus-gate --plant: FAIL -- " + "; ".join(bad), file=sys.stderr)
            return FAIL
        print("pincensus-gate --plant: the file pintable executes is not NO-SUBJECT-DECLARED; "
              "a copy with no binding is; a hex pin is not an expectation row; "
              "meta['rows'] is unchanged")
        return PASS
    finally:
        shutil.rmtree(base, ignore_errors=True)


def plant():
    """Attack copies. The live tree is opened for nothing and never written.

    TWO CLAIMS, AND EACH ONE CAN FAIL ON ITS OWN:

      1 An expectation row whose scan and declaration disagree is not a hex pin.
      2 A hex pin is not an expectation row.

    The control is the same file with no rebinding. A census that says DISAGREE for
    both, or that carries one value on both sides, fails: the first is a label, the
    second is a vacuous negative.

    AND THE SUBJECT, ON COPIES: the file pintable executes is not
    NO-SUBJECT-DECLARED. A copy with no artifact binding is. `meta["rows"]`
    does not move.
    """
    subject = plant_subject()
    base = tempfile.mkdtemp(prefix="pincensus-expect-plant-")
    try:
        control, planted = (os.path.join(base, name) for name in ("control", "planted"))
        for dest, extra in ((control, ""), (planted, _PLANT_REBIND)):
            os.makedirs(dest)
            with open(os.path.join(dest, "pins.py"), "w", encoding="utf-8") as fh:
                fh.write(_PLANT_BODY + extra)
        c_rows, c_meta = census(control, ROOT, scratch=True)
        p_rows, p_meta = census(planted, ROOT, scratch=True)
        c_ex, p_ex = c_meta["expectation-rows"], p_meta["expectation-rows"]
        c_hex, p_hex = _values(c_rows), _values(p_rows)
        c_exp, p_exp = _values(c_ex), _values(p_ex)
        c_row, p_row = _one(c_ex, _PLANT_SCAN), _one(p_ex, _PLANT_DECLARED)
        bad = []
        if c_row is None or p_row is None:
            bad.append("a side produced no expectation row, so the plant compared nothing")
        if _PLANT_DIGEST not in c_hex or _PLANT_DIGEST not in p_hex:
            bad.append("the hex pin was not counted as a hex pin, so the split was not tested")
        if _PLANT_SCALAR not in c_hex or _PLANT_SCALAR not in p_hex:
            bad.append("the scalar hex pin was not counted as a hex pin")
        if c_exp == p_exp:
            bad.append("VACUOUS: control and plant carry the same expectation values")
        if p_row is not None and "DISAGREE" not in p_row["detail"]:
            bad.append("the plant did not observe a scan/declaration disagreement")
        if c_row is not None and "DISAGREE" in c_row["detail"]:
            bad.append("the control reported a disagreement it does not have")
        if _PLANT_DECLARED in p_hex or _PLANT_SCAN in c_hex or _PLANT_SCAN in p_hex:
            bad.append("an expectation row was counted as a hex pin")
        if _PLANT_DIGEST in c_exp or _PLANT_DIGEST in p_exp or _PLANT_SCALAR in c_exp or _PLANT_SCALAR in p_exp:
            bad.append("a hex pin was counted as an expectation row")
        if any(r.get("shape") == "EXPECTATION" for r in p_rows):
            bad.append("a hex-pin row was shaped as an expectation")
        if c_meta["rows"] != len(c_rows) or p_meta["rows"] != len(p_rows):
            bad.append("meta['rows'] does not mean the hex-pin rows")
        if c_ex is c_rows or p_ex is p_rows:
            bad.append("the two populations are one list")
        if c_row is not None and c_row["currency"] != "NO-SUBJECT-DECLARED":
            bad.append("a table with no reader was given a subject")
        if p_row is not None and p_row["currency"] != "NO-SUBJECT-DECLARED":
            bad.append("a rebinding was read as a subject")
        print("pincensus-gate --plant: synthetic mixed table, scan %r declared %r" % (
            _PLANT_SCAN, _PLANT_DECLARED))
        print("  CONTROL  expectation=%s hex-has-digest=%s hex-has-expectation=%s" % (
            None if c_row is None else c_row["value"], _PLANT_DIGEST in c_hex, _PLANT_SCAN in c_hex))
        print("  PLANT    expectation=%s detail-disagrees=%s hex-has-expectation=%s" % (
            None if p_row is None else p_row["value"],
            False if p_row is None else "DISAGREE" in p_row["detail"],
            _PLANT_DECLARED in p_hex))
        print("  hex pin in expectation rows: control=%s plant=%s" % (
            _PLANT_DIGEST in c_exp, _PLANT_DIGEST in p_exp))
        if bad:
            print("pincensus-gate --plant: FAIL -- " + "; ".join(bad), file=sys.stderr)
            return FAIL
        print("pincensus-gate --plant: the disagreed expectation is not a hex pin, "
              "and the hex pin is not an expectation row")
        return subject
    finally:
        shutil.rmtree(base, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--scratch", action="store_true",
                    help="treat --root as a corpus that is not a git tree")
    ap.add_argument("--no-write", action="store_true")
    ap.add_argument("--plant", action="store_true",
                    help="prove the flagship subject, the copy refusal, and that a hex pin is not an expectation row")
    args = ap.parse_args()
    if args.plant:
        return plant()

    rows, meta = census(args.root, ROOT, args.scratch)
    if not rows:
        print("pincensus-gate: DEAD -- the census emitted no rows", file=sys.stderr)
        return DEAD
    stamp = "NOT WRITTEN (--no-write)"
    exrows = meta.get("expectation-rows") or []
    if not args.no_write:
        stamp = write_rows(rows, meta)
        write_expectation_rows(exrows, meta)

    reach = reachability()
    c = meta["classes"]
    out = sys.stdout
    out.write("pincensus-gate: A CENSUS OF EVERY PIN IN THE TREE\n")
    out.write(f"  generated {stamp} HEAD={git(ROOT, 'rev-parse', '--short', 'HEAD')}\n")
    out.write(f"  population (os.walk + UTF-8 decode, bounded by `git ls-tree -r HEAD`): "
              f"{meta['counts'].get('walk-decoded')} walked, "
              f"{meta['counts'].get('in-both', meta['counts'].get('walk-decoded'))} in both, "
              f"{meta['counts'].get('tree-tracked')} in the tree\n")
    if meta["hosts"]:
        h = meta["hosts"]
        out.write(f"  host language by CONTENT (ast.parse): {h['by-host']}; "
                  f"error budget: {h['py-extends-host-prose']} .py read as prose, "
                  f"{h['md-parses-as-python']} .md read as python {h['md-examples']}\n")
    out.write(f"  named pin sites: {meta['sites']}   prose pin lines: {meta['prose-lines']}"
              f"   rows: {meta['rows']}\n")
    exmeta = meta.get("expectations") or {}
    out.write(f"  EXPECTATION ROWS, NOT ADDED TO rows: {len(exrows)}"
              f"   tables: {exmeta.get('tables', 0)}"
              f"   scan/declaration disagree: {exmeta.get('disagreeing', 0)}\n")
    out.write("    a hex pin is not in this count; an expectation is not in the hex-pin count\n")
    for k, v in sorted((exmeta.get("currency") or {}).items(), key=lambda kv: -kv[1]):
        out.write(f"    {k:28} {v:5}\n")
    out.write("\n")

    out.write("  THE THREE KINDS OF WRONG -- SEPARATE POPULATIONS, SEPARATE REMEDIES\n")
    for kind, what in (("CAN-FAIL", "a regression row: code reads it, so stale goes red"),
                       ("CANNOT-FAIL", "the artefacts_ok() class: a literal no code reads"),
                       ("PROSE-ONLY", "prose is the only copy; nothing can re-derive it"),
                       ("PROSE-SHADOW", "prose echoing a pin code already holds")):
        out.write(f"    {kind:14} {c.get(kind, 0):5}   {what}\n")
    out.write(f"    of which byte-identical to refs/remotes/upstream/master (UPSTREAM's pins, "
              f"read against the ref, NOT fetched): {meta['origin'].get('UPSTREAM', 0)} rows\n")
    out.write("\n  CURRENCY\n")
    for k, v in sorted(meta["currency"].items(), key=lambda kv: -kv[1]):
        out.write(f"    {k:20} {v:5}\n")

    out.write("\n  DOES A PIN GOING STALE MAKE ANYTHING GO RED BY ITSELF?\n")
    out.write(f"    .git/hooks non-.sample files : {reach['git-hooks-non-sample']}\n")
    out.write(f"    core.hooksPath              : {reach['core.hooksPath']}\n")
    out.write(f"    .github/workflows            : {reach['workflows']} files, "
              f"{len(reach['workflows-naming-a-gate'])} name a gate "
              f"{reach['workflows-naming-a-gate']}\n")
    out.write(f"    gates/artifacts tracked      : {reach['gates-artifacts-tracked']} "
              "(gitignored, so a fresh clone has none)\n")
    out.write("    ANSWER: NOTHING. Not because the pins are right, and not because the\n")
    out.write("    comparators are wrong -- because on a fresh clone no hook, no workflow\n")
    out.write("    and no tracked artifact invokes ANY gate. A pin CAN fail (see CAN-FAIL);\n")
    out.write("    whether anyone is present to see it is a separate fact, and it is not\n")
    out.write("    derivable from the tree.\n")

    if not meta["sites"] and not meta["prose-lines"]:
        print("pincensus-gate: REFUSED -- the population is empty", file=sys.stderr)
        return REFUSED
    return PASS


if __name__ == "__main__":
    sys.exit(main())