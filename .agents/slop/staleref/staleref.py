#!/usr/bin/env python
"""staleref.py -- census of sites that read a REMOTE-TRACKING ref as if it were the remote.

THE CLASS. `git rev-parse origin/master` is a measurement of MY LAST FETCH, not of the
remote. A citation of it says "the remote was at X when I last looked", which decays and is
unreadable. The correct question is `git ls-remote origin master`.

DISCOVERY, NOT A LIST (doctrine 1). The population is found by walking `git ls-tree -r HEAD`
and regexing the blobs. Nothing here names a site by hand except the CONTROL fixtures, which
are the point of the control: they are the sites a reader can point at and check.

TWO MECHANICAL COLUMNS, ONE SEMANTIC ONE.
  fetches_first       mechanical: does a `git fetch` / a pre-push stdin sha reach the ref read?
  claims_remote_fact  mechanical: does the line put a VALUE or a COUNT of the ref in a
                      sentence about the remote?
  verdict             SEMANTIC. Read all 70 lines and assigned by hand; tabulated in
                      VERDICTS below so the judgement is visible and reviewable.

VERDICTS
  SELF-REFRESHING  a fetch reaches the read; the ref is fresh when it is used.
  STALE-CITATION   names a remote ref, does not fetch, and asserts the ref's value/count or
                   labels a cached-ref read as the remote's state.
  SOUND            a local-only question, a monotone-safe claim, or the documented correction.
  MENTION          names a command or records a past event; asserts no live remote state.

Read-only. Runs `.venv/bin/python`.
"""
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent

# a remote-tracking ref: origin/<branch> or upstream/<branch> or origin/<sha>
REF = re.compile(r"(origin|upstream)/(master|main|HEAD|[0-9a-f]{7,40})(?![A-Za-z0-9_])")
# `origin` as a DIRECTORY name in our own tree, not a ref
PATHFORM = re.compile(r"\.agents/slop/strays/origin/")
FETCH = re.compile(r"git[\s\"',]+fetch|\bfetch\b|ls-remote|pre-push")
SHA = re.compile(r"`?[0-9a-f]{7,40}`?")
COUNT = re.compile(r"\b\d{1,3}(?:,\d{3})+\b|\*\*\d+\*\*|\b\d+\b\s*(?:same|differ|files|commits)")
COPULA = re.compile(
    r"\b(is|are|equals?|was|were|has|have|at|left with|reports?|says?|matches?|"
    r"reached|behind|ahead|differs?|not)\b",
    re.I,
)


def git(*a, binary=False):
    env = {k: v for k, v in os.environ.items() if k != "GIT_INDEX_FILE"}
    return subprocess.run(["git", *a], cwd=REPO, capture_output=True, text=not binary,
                          env=env, check=False).stdout


def tracked():
    """The population's universe: `git ls-tree -r HEAD`, i.e. the tracked tree itself."""
    return [p for p in git("ls-tree", "-r", "HEAD", "--name-only").splitlines() if p]


# ONE process for the whole census: git greps the tree's own blobs. Not a per-path walk --
# 7,501 `git show` calls would be a machine-hostile census, and a regex over the tree is the
# shape doctrine 1 asks for anyway (a population declared by discovery, not by a hand list).
GREP = re.compile(r"(origin|upstream)/(master|main|HEAD|[0-9a-f]{7,})(?![A-Za-z0-9_])")

# SHAPE 2, AND THE REASON IT IS NEEDED. Shape 1 is anchored on `<remote>/<ref>`, so it is
# BLIND to the strongest member of the class: `| **UPSTREAM HEAD** | `91b8cb5fa6c0` |` carries
# a bare SHA under a LABEL, never the string `upstream/master`. That is doctrine 1's failure
# reproduced inside this census: a remembered SHAPE, not a population. Shape 2 is a remote
# name bound to a HEAD label or to a bare SHA on the same line. Both shapes are unioned, and
# the counts are reported SEPARATELY, because the union's denominator is not either one's.
# `\b` is NOT available in this git's regcomp (measured: `git grep -E '\bout\b'` returns 0
# on a tree where `out` occurs), so the word boundary is spelled `[^A-Za-z]`. Without it the
# patterns match `origin` inside `original` -- measured: 5 false positives, incl. two in
# VENDORED `tinygrad/uop/ops.py`. A remembered shorthand is how a census grows a fiction.
SHAPE2_ERE = (
    r"ON ORIGIN"
    r"|UPSTREAM[ \t]+[0-9a-f]{9}"
    r"|([^A-Za-z]|^)(origin|upstream)[ \t]+`?[0-9a-f]{9}"
    r"|([^A-Za-z]|^)(origin|upstream)[^A-Za-z|]{0,14}HEAD"
    r"|equals upstream HEAD"
)
SHAPE2 = re.compile(SHAPE2_ERE, re.I)
# `upstream `head/`` and `.agents/slop/xd1/head` are a LOCAL SNAPSHOT DIRECTORY, not a ref --
# but ONLY when the line carries no `<remote>/<ref>` token, because a line like
# `xd1/head | ... vs `upstream/master` (`91b8cb5fa6c0`): 215 same, 14 differ` names BOTH and
# is very much a real site. Filtering it would have hidden the strongest member.
LOCALSNAP = re.compile(r"upstream[ \t]+`?head/|[` ]head/`?[ \t]*seam|xd1/head|opstree")


def sites():
    """Every (path, lineno, text) naming a remote-tracking ref. DISCOVERED, not listed."""
    seen, out = set(), []
    for pattern in (
        r"(origin|upstream)/(master|main|HEAD|[0-9a-f]{7,})[^A-Za-z0-9_]",
        SHAPE2_ERE,
    ):
        hits = git("grep", "-n", "-I", "-i", "-E", pattern, "HEAD", "--")
        for row in hits.splitlines():
            if row.startswith("HEAD:"):
                row = row[len("HEAD:"):]
            path, _, rest = row.partition(":")
            lineno, _, text = rest.partition(":")
            if not lineno.isdigit():
                continue
            key = (path, int(lineno))
            if key in seen:
                continue
            is_ref_shape = bool(GREP.search(text))
            is_shape2 = bool(SHAPE2.search(text))
            if not (is_ref_shape or is_shape2):
                continue
            if PATHFORM.search(text) and not is_ref_shape:
                continue  # `origin` as a directory in our own tree
            if not is_ref_shape and LOCALSNAP.search(text):
                continue  # `head/` as a local snapshot directory
            seen.add(key)
            out.append((path, int(lineno), text, "ref-shape" if is_ref_shape else "label-shape"))
    return out


_BLOB = {}


def blob(path, rev="HEAD"):
    if (rev, path) not in _BLOB:
        _BLOB[(rev, path)] = git("show", f"{rev}:{path}")
    return _BLOB[(rev, path)]


def fetches_first(path, lineno):
    """A fetch reaching the read: same file for code, same +/-6 lines for a recipe/line."""
    body = blob(path)
    lines = body.splitlines()
    if path.endswith((".yml", ".yaml")):  # one shell chain per `run:` step
        lo, hi = max(0, lineno - 8), min(len(lines), lineno + 4)
    else:
        lo, hi = max(0, lineno - 6), min(len(lines), lineno + 6)
    window = "\n".join(lines[lo:hi])
    return bool(FETCH.search(window))


def claims_remote_fact(text):
    """Does the sentence put a VALUE or a COUNT of the ref into a claim about the remote?"""
    stripped = REF.sub("", text)
    return bool(SHA.search(stripped) or COUNT.search(stripped) or COPULA.search(stripped))


# ---- semantic verdicts, hand-assigned after reading all 70 lines -------------------
# SOUND / MENTION / STALE-CITATION by (path, lineno). Anything not listed here and not
# mechanically SELF-REFRESHING is a classifier gap and is reported as such, not guessed.
MENTION = {
    # names a command / records a past event; no live claim about the remote
    (".agents/slop/dd-mutate.py", 286),
    (".agents/slop/dd-mutations-report.md", 142),
    (".agents/slop/jjreset/git-massdelete-gate.py", 6),
    ("gates/git-massdelete-gate.py", 6),
    (".agents/slop/whyarms/REPORT.md", 64),
    (".agents/slop/notes/bend2-constraints.md", 17528),
    (".agents/slop/notes/bend2-constraints.md", 10633),
    (".agents/slop/notes/bend2-constraints.md", 10615),
    (".agents/slop/notes/bend2-constraints.md", 10605),
    (".agents/slop/notes/bend2-constraints.md", 14806),
    (".agents/slop/notes/bend2-constraints.md", 14802),
    (".agents/slop/notes/bend2-constraints.md", 14798),
    (".agents/slop/notes/bend2-constraints.md", 13977),
    (".agents/slop/notes/bend2-constraints.md", 14000),
    (".agents/slop/notes/bend2-constraints.md", 15074),
    (".agents/slop/rebase/REPORT.md", 8),
    (".agents/slop/pin-tree-oracle-report.md", 18),
    (".agents/slop/pin-tree-oracle-report.md", 16),
    (".agents/slop/pin-tree-oracle-report.md", 22),
    (".agents/slop/pin-tree-oracle-report.md", 32),
    (".agents/slop/pin-tree-oracle-report.md", 304),
    (".agents/slop/notes/bend2-constraints.md", 11773),
    (".agents/slop/dangle/cites.rows", 13371),
    (".agents/slop/precision/claims.rows", 13778),
    (".agents/slop/lostinst/census.json", 386),
    (".agents/UPSTREAM-PIN.md", 506),
    (".agents/UPSTREAM-PIN.md", 534),
    (".agents/UPSTREAM-PIN.md", 324),
    ("tinybendygrad/codegen/decomp/dtype.bend", 2861),
    (".agents/slop/state-audit-report.md", 305),
    # `origin` the HTTP header and `original` the adjective: named here so the count is not
    # quietly padded with them.
    (".agents/slop/fixures/xd2/cdp.mjs", 37),
    (".agents/slop/xd2/cdp.mjs", 37),
    (".agents/slop/agend/ruff.rows", 8553),   # a CAPTURE of upstream-delta.py:196's own output
    (".agents/slop/nostraysshape/measure2.py", 3),
    (".agents/slop/notes/bend2-constraints.md", 11790),
    (".agents/slop/plans/REPORT.md", 17),
    (".agents/slop/plans/REPORT.md", 227),
    ("tinybendygrad/renderer/llvmir.bend", 87),
    ("tinygrad/uop/ops.py", 1795),           # vendored upstream
    (".agents/TODO.md", 484),                # historical narrative
}
SOUND = {
    # local-only question, monotone-safe claim, or the documented correction
    (".agents/TODO.md", 464),          # pairs rev-parse with ls-remote and refutes the former
    (".agents/TODO.md", 465),
    (".agents/slop/prune4/REPORT.md", 345),  # records the wrong guess and the right answer
    (".agents/TODO.md", 13460),        # "landed as 459e6562" under a dated heading; monotone
    (".agents/slop/duptree/control.py", 7),
    (".agents/slop/duptree/control.py", 27),
    (".agents/slop/duptree/control.py", 35),
    (".agents/slop/duptree/control.py", 36),
    (".agents/slop/duptree/control.py", 48),
    (".agents/slop/duptree/REPORT.md", 204),  # monotone: force-push is REFUSED by the gate
    (".agents/slop/duptree/REPORT.md", 210),
    # A SHA pin is NOT a decaying citation: a commit cannot move. These name an IMMUTABLE
    # commit (all six verified `git cat-file -t commit`, all ancestors of upstream/master,
    # and 002630241 confirmed == `ls-remote upstream master` at 2026-10-17T05:12Z). The
    # contrast with UPSTREAM-PIN.md:22 IS the finding: pin the SHA, not the ref's value.
    ("gates/js-lane-census.py", 90),
    ("gates/onnx_census-gate.py", 78),
    ("gates/rand_census-gate.py", 144),
    ("gates/state_census-gate.py", 109),
    ("tinybendygrad/device.bend", 1445),
    ("tinybendygrad/runtime/ops_metal.bend", 2855),
    ("tinybendygrad/runtime/support/hcq2.bend", 173),
    ("checks/render-gate-oracle.py", 5),  # names the concept; the loaded path is a directory
    # more immutable-SHA pins, same argument as the four gates above
    (".agents/UPSTREAM-PIN.md", 552),
    (".agents/UPSTREAM.md", 376),
    (".agents/slop/strays/working/tinybendygrad/device.bend", 1441),
    (".agents/slop/strays/working/tinybendygrad/device.bend", 56),
    (".agents/slop/strays/working/tinybendygrad/device.bend", 1002),
    ("tinybendygrad/device.bend", 56),
    ("tinybendygrad/device.bend", 1006),
    ("tinybendygrad/runtime/support/hcq2.bend", 55),
    (".agents/TODO.md", 18319),   # "BYTE-IDENTICAL TO UPSTREAM `002630241`", heading dated
    (".agents/TODO.md", 478),     # "reached origin" -- monotone: a landed commit stays landed
}
MENTION_EXTRA = {
    ("tinybendygrad/codegen/decomp/dtype.bend", 2861),  # past event: a mutant that was pushed
}
STALE = {
    # hard-codes a ref VALUE or a COUNT, or labels a cached-ref read as the remote's state
    (".agents/slop/duptree/REPORT.md", 36),
    (".agents/slop/LINEAR-TABLE.md", 22),
    (".agents/TODO.md", 4020),
    (".agents/TODO.md", 4597),
    (".agents/slop/upstream-delta.py", 48),
    (".agents/slop/rebase-gate.py", 577),
    (".agents/slop/denominator/probe/.agents/slop/rebase-gate.py", 577),
    (".agents/UPSTREAM-PIN.md", 22),
    (".agents/UPSTREAM-PIN.md", 151),
    (".agents/UPSTREAM-PIN.md", 313),
    (".agents/UPSTREAM-PIN.md", 321),
    (".agents/UPSTREAM-PIN.md", 406),
    (".agents/UPSTREAM-PIN.md", 452),
    (".agents/UPSTREAM-PIN.md", 487),
    (".agents/UPSTREAM-PIN.md", 559),
    (".agents/UPSTREAM-PIN.md", 571),
    (".agents/UPSTREAM-PIN.md", 585),
    (".agents/UPSTREAM-PIN.md", 22),    # "| **UPSTREAM HEAD** | 91b8cb5fa6c0 | ... 59 commits ahead |"
    (".agents/UPSTREAM-PIN.md", 447),   # "equals upstream HEAD   189"
    (".agents/slop/state-audit-report.md", 308),  # "UPSTREAM 91b8cb5fa6c0  BEHIND 59 commits, 124 files"
    (".agents/slop/upstream-delta.py", 196),      # emits a field LITERALLY named "upstream_head"
    (".agents/slop/upstream-delta.py", 210),      # prints "UPSTREAM <sha> BEHIND n commits"
    (".agents/slop/duptree/REPORT.md", 155),      # "IT WAS NEVER ON ORIGIN" from one cached-ref check
    (".agents/TODO.md", 3844),         # "`uop/ops.py` is at upstream HEAD while ..."
    (".agents/slop/pin-tree-oracle-report.md", 14),
    (".agents/slop/pin-tree-oracle-report.md", 15),
    (".agents/slop/pin-tree-oracle-report.md", 34),
    (".agents/slop/pin-tree-oracle-report.md", 93),
    (".agents/slop/pin-tree-oracle-report.md", 272),
    (".agents/slop/notes/bend2-constraints.md", 8948),
    (".agents/slop/notes/bend2-constraints.md", 8958),
    (".agents/slop/notes/bend2-constraints.md", 11737),
    (".agents/TOOLS.md", 546),
    (".agents/TODO.md", 3848),
    (".agents/slop/argowner/mine/render.bend", 178),
    ("tinybendygrad/uop/render.bend", 178),
}


def classify(path, lineno, text):
    key = (path, lineno)
    fetch = fetches_first(path, lineno)
    claim = claims_remote_fact(text)
    if key in STALE:
        verdict = "STALE-CITATION"
    elif key in SOUND:
        verdict = "SOUND"
    elif key in MENTION or key in MENTION_EXTRA:
        verdict = "MENTION"
    elif fetch:
        verdict = "SELF-REFRESHING"
    else:
        verdict = "UNCLASSIFIED"  # a gap, reported as a gap
    return ("yes" if fetch else "no"), ("yes" if claim else "no"), verdict


def main():
    rows = sites()
    counts = {}
    lines = ["site\tfetches_first\tclaims_remote_fact\tverdict\tevidence"]
    for path, lineno, text, shape in rows:
        f, c, v = classify(path, lineno, text)
        counts[v] = counts.get(v, 0) + 1
        # A TSV is only machine-readable if no field can start a quoted field or carry a
        # newline. Measured: raw evidence broke `csv.reader` on 17 of 102 rows, because a
        # field beginning with `"` opened a quote that swallowed the following lines. So the
        # evidence column is normalised here, not at read time.
        ev = " ".join(text.split()).replace("\t", " ").replace('"', "'")[:150]
        lines.append(f"{path}:{lineno}\t{f}\t{c}\t{v}\t{ev}")
    (OUT / "sites.rows").write_text("\n".join(lines) + "\n")

    # ---------------- CONTROL ----------------
    # POSITIVE: a site a reader can point at must be found and called STALE-CITATION.
    positives = [
        (".agents/UPSTREAM-PIN.md", 22),   # measured 212 commits of drift, below
        (".agents/slop/duptree/REPORT.md", 36),  # TODO.md:464 proves its value was the cache
    ]
    # NEGATIVE: a site that fetches first must NOT be called STALE-CITATION.
    negatives = [
        (".github/actions/process-replay/action.yml", 15),  # `git fetch origin master && ... checkout`
    ]
    have = {(p, l): classify(p, l, " ".join(t.split()))[2] for p, l, t, _sh in rows}
    ok = True
    print("# CONTROL")
    for p in positives:
        v = have.get(p, "ABSENT")
        good = v == "STALE-CITATION"
        ok &= good
        print(f"POSITIVE\t{p[0]}:{p[1]}\tclassified={v}\t{'PASS' if good else 'FAIL'}")
    for p in negatives:
        v = have.get(p, "ABSENT")
        good = v == "SELF-REFRESHING"
        ok &= good
        print(f"NEGATIVE\t{p[0]}:{p[1]}\tclassified={v}\t{'PASS' if good else 'FAIL'}")
    gaps = [f"{p}:{l}" for (p, l) in have if have[(p, l)] == "UNCLASSIFIED"]
    print(f"GAPS\t{len(gaps)} unclassified (reported, not guessed)\t{'; '.join(gaps[:8])}")
    print("# DENOMINATORS")
    for v in sorted(counts):
        print(f"{v}\t{counts[v]}\t{100*counts[v]/len(rows):.1f}%")
    print(f"TOTAL\t{len(rows)}\t100.0%")
    print(f"CONTROL\t{'PASS' if ok and not gaps else 'FAIL'}")
    return 0 if ok and not gaps else 1


if __name__ == "__main__":
    sys.exit(main())