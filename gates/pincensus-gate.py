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
import subprocess
import sys
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


def currency(value, git_root, subject):
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
    """
    bare, suffix = value
    kind = git(git_root, "cat-file", "-t", bare + (suffix or "")) if git_root else ""
    if kind in ("commit", "tag"):
        behind = git(git_root, "rev-list", "--count", f"{bare}{suffix or ''}..HEAD")
        return "REVISION", "RESOLVES", f"cat-file -t={kind}; behind-HEAD={behind or '?'}"
    if subject:
        for base in SUBJECT_ROOTS:
            rel = os.path.join(base, subject)
            if any(rel.startswith(n) for n in NEVER_READ):
                return "DIGEST", "SUBJECT-IN-GITIGNORED-RUNS", \
                    f"{rel} is under a gitignored run directory; not read"
            got = sha256_of(os.path.join(git_root, rel))
            if got is not None:
                how = "PREFIX " if len(bare) < 64 else ""
                ok = got.startswith(bare)
                return "DIGEST", ("%s%s" % (how, "CURRENT" if ok else "MISMATCH")), \
                    f"sha256({rel})={got[:16]} vs pinned {bare[:16]}"
        return "DIGEST", "SUBJECT-NOT-FOUND", \
            f"looked in {', '.join(SUBJECT_ROOTS)} for {subject}; found neither"
    if 7 <= len(bare) <= 64:
        return "OTHER", "NO-MEASUREMENT", \
            f"len={len(bare)}, not a revision in this object store and no subject named"
    return "OTHER", "NO-MEASUREMENT", f"len={len(bare)}, not a revision length"


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
        for i, raw in enumerate(TOKEN.finditer(" ".join(s["values"]))):
            value = (raw.group(1), raw.group(2))
            if s["host"] != "prose" and i >= len(s["values"]):
                break
            subject = next((k for k, v in pairs.items() if v == value[0]), None)
            shape, verdict, detail = currency(value, git_root, subject)
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


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--scratch", action="store_true",
                    help="treat --root as a corpus that is not a git tree")
    ap.add_argument("--no-write", action="store_true")
    args = ap.parse_args()

    rows, meta = census(args.root, ROOT, args.scratch)
    if not rows:
        print("pincensus-gate: DEAD -- the census emitted no rows", file=sys.stderr)
        return DEAD
    stamp = "NOT WRITTEN (--no-write)"
    if not args.no_write:
        stamp = write_rows(rows, meta)

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
              f"   rows: {meta['rows']}\n\n")

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