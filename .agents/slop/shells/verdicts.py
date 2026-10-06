#!/usr/bin/env python3
"""verdicts.py -- classify `rootcheck.sh` runs from the evidence it captured.

    .venv/bin/python .agents/slop/shells/verdicts.py <tree> <rundir> [more rundirs...]

WHY A SECOND PASS, AND WHY IT IS NOT A RETRY. The first cut of the classifier flagged any
absolute path outside the tree, which a harness is supposed to notice and a reader is
supposed to distrust: six of the scripts legitimately write scratch files under `$TMPDIR`,
and `$TMPDIR` on this machine is `/var/folders/.../T/`, so every one of them was reported
WRONG-ROOT for a path they own. A classifier that cries wolf on a harness's own scratch
directory is the same defect as a tokenizer that ate a full stop -- it is wrong about the
thing it is looking at, and it is wrong in the direction that makes the report useless.

So the rule is stated as a PROPERTY OF THE PATH rather than as a pattern over the output:

    WRONG-ROOT  the script named, outside `<tree>`, a path that belongs to the repository
                -- a component of `tinybendygrad`, `pyproject.toml`, `checks/`, `bin/bend`,
                `references/`, `.venv/bin/python`. Those are the markers the scripts'
                own root assertions test for, so naming one of them outside the tree IS the
                defect, and nothing else is.

Nothing is inferred from the exit status alone. rc=142 is the harness's own alarm and is
ALARM, never a pass. rc=0 is not automatically a pass either: a script that ran nothing and
exited 0 is the failure this whole exercise is about, so rc=0 is only RAN when the output
shows it did its own work.

  .venv/bin/python .agents/slop/shells/verdicts.py $TREE before after
"""
from __future__ import annotations

import os
import pathlib
import re
import sys

# A repository path, as opposed to a scratch path. These are the same markers the shims
# assert on, deliberately: the classifier and the fix cannot disagree about what the tree is.
REPO_MARKERS = ("tinybendygrad", "pyproject.toml", "/checks/", "/bin/bend", "/references/",
                ".venv/bin/python")
# Directories a repo path may start at, for deciding whether a complained-about path is a
# REPOSITORY path at all. `.agents/` is here because the frozen oracles and the generated
# fixtures live under it and several gates read them; without it, `gate.sh`'s
# `.agents/slop/shlscope/gen.py` had no marker and was classified as neither present nor
# absent, which is how a missing collaborator came out as a generic failure.
REPO_ROOTS = ("tinybendygrad", "checks", ".agents", "bin", "references", "runs", "gates",
              "oracles", "examples", "extra", "docs", "langs", "spec", "test", "tools")
# The scripts' own words for "I measured nothing", which is a PASS for root-finding.
REFUSALS = ("REFUSED, NOT A VERDICT", "REFUSING", "REFUSED", "PASS WITH")
ABS = re.compile(r"(?:/Users|/private|/var|/tmp|/opt)[A-Za-z0-9_./+-]*")
# A path named ON A LINE THAT COMPLAINS. Anchoring to the line is the whole point: a
# `[A-Za-z0-9_.-]*` scan of the whole output is how one tokenizer in this repo ate a full stop,
# and an unanchored scan here would flag every file a script merely mentions -- `checks/
# bounded.py` exists in the tree, so `bounded-selftest.sh` would report WRONG-ROOT while
# passing. A rule that fires on a script's ordinary output cannot measure a defect.
COMPLAINTS = ("No such file or directory", "can't open file", "cannot open", "not found",
              "Is a directory", "Permission denied", "no such file")
# NOT "something with a dot in it". `./bin/bend` and `.venv/bin/python` are the two paths this
# rule exists to catch and NEITHER HAS AN INTERNAL DOT -- a dot-requiring tokeniser misses both,
# which is the same class of bug as the one that ate a full stop. So: any run of path characters
# containing at least one word character, and let `(tree / p).exists()` do the deciding. A
# permissive extractor plus an exact predicate beats a clever extractor.
PATHISH = re.compile(r"[A-Za-z0-9_./+-]*[A-Za-z0-9_-][A-Za-z0-9_./+-]*")


def complained_about(text: str) -> set[str]:
    return {p for line in text.splitlines() if any(c in line for c in COMPLAINTS)
            for p in PATHISH.findall(line)}


def paths_in_tree(tree: str, text: str) -> tuple[set[str], set[str]]:
    """Complained-about paths, split into (present in the tree, absent from it entirely).

    `gate.sh` says it cannot open `.agents/slop/shlscope/gen.py`; `run-all.sh` says it cannot
    open `checks/derive.py`. Both are already repo-relative, so a direct `exists()` decides
    them. A tree that resolves `$0` to an absolute path is handled by taking the trailing
    components, because a relative spelling is what these messages use.
    """
    root = pathlib.Path(tree)
    present, absent = set(), set()
    for p in complained_about(text):
        # Walk every suffix of the path, longest first. A fixed two-or-three-component guess is
        # wrong the moment a unit nests one level deeper, and a rule that silently stops
        # matching is a rule that stops measuring: `gate.sh` names an ABSOLUTE path, whose last
        # three components are `slop/shlscope/gen.py`, not the `.agents/slop/shlscope/gen.py` a
        # relative spelling would have given.
        parts = pathlib.Path(p).parts
        # A path under the tree that the tree DOES have is the script quoting its own `$0` in
        # a diagnostic, which is no evidence about which root it reached. A path under the
        # tree that the tree does NOT have is the ordinary ABSENT-INPUT case, so only the
        # first kind is skipped.
        if p.startswith(tree) and pathlib.Path(p).exists():
            continue
        for n in range(len(parts), 0, -1):
            suffix = pathlib.Path(*parts[-n:]).as_posix()
            if not (suffix.startswith(REPO_ROOTS) or any(m in suffix for m in REPO_MARKERS)):
                continue              # not a repository path; keep shrinking
            (present if (root / suffix).exists() else absent).add(suffix)
            break
    return present, absent


# Where a script is ALLOWED to name a `tinybendygrad` that is not the tree: its own workdir
# under $TMPDIR, and the harness's own evidence directory. `run-port-mm.sh` builds a full
# copy of the port at `$TMPDIR/e2e-port-mm/copy/tinybendygrad` by design, and calling that a
# misresolved root is the classifier failing on the tree's own convention rather than on the
# defect. `$TMPDIR` on this machine ends in `/`, hence the doubled slashes in the output --
# several of these scripts spell their workdir `${TMPDIR}name` without a separator.
SCRATCH = tuple(d for d in (os.environ.get("TMPDIR"), str(pathlib.Path(__file__).parent))
                if d)


def read(run: pathlib.Path, script: str) -> str:
    """This script's OWN two files, and no others.

    The first cut globbed `run/*.out` and `run/*.err`, so every script's verdict was computed
    from the whole run directory -- and `e2e.sh`, the one script that is still broken, put its
    out-of-tree `.venv` path into every other script's verdict. Seventeen out-of-tree paths
    where there was one. **One method consuming another method's data is a false result, and it
    is false in the direction that hides the answer.**
    """
    return "".join((run / f"{script}{ext}").read_text(errors="replace")
                   for ext in (".out", ".err") if (run / f"{script}{ext}").exists())


def classify(tree: str, run: pathlib.Path, script: str, rc: int) -> tuple[str, str]:
    if rc == 142:
        return "ALARM", "the harness's own alarm (rc=142); it proves only that it started"
    text = read(run, script)
    outside = sorted({p for p in ABS.findall(text)
                      if not p.startswith(tree) and not p.startswith(SCRATCH)
                      and any(m in p for m in REPO_MARKERS)})
    if outside:
        return "WRONG-ROOT", f"named a repo path outside the tree: {outside[0]}"
    # THE SECOND MECHANISM, AND IT IS NOT A SHARER OF THE FIRST. Rule 1 needs the script to
    # LEAK an absolute path, and a script that cds to the wrong root and then fails on a
    # RELATIVE path leaks nothing: `zsh: ./bin/bend: No such file or directory` and Python's
    # `can't open file '.agents/slop/shlscope/gen.py'` both look like an ordinary missing input.
    # So: take every path the run complained about, and ASK THE TREE whether it is there. One
    # that exists in the tree and could not be opened is a script that is not in the tree.
    # Rule 1 reads the output; this one stats the filesystem, so being wrong about the output
    # cannot make this one wrong too.
    present, absent = paths_in_tree(tree, text)
    for rel in sorted(present):
        return "WRONG-ROOT", f"could not open {rel}, which the tree HAS -- it is not in the tree"
    if rc != 0:
        for line in text.splitlines():
            if any(t in line for t in REFUSALS):
                return "REFUSED", line.strip()[:100]
        # A missing COLLABORATOR is not the same finding as a missing input, and lumping them
        # together hides both. `gate.sh` asks for `.agents/slop/shlscope/gen.py` and `run-all.sh`
        # for `checks/derive.py`; neither is in this tree at all, tracked or not, so no root
        # could have supplied them. Ask the TREE which it is.
        for p in sorted(absent):
            return "ABSENT-INPUT", f"needs {p}, which this tree does not contain at all"
        # A `FileNotFoundError` whose path is under the SCRATCH tree is the wrong-root signature
        # one level removed. `lint_demo.sh` copies `.agents/slop` out of the tree into a $TMPDIR
        # workdir and then reads the copy; when its root was wrong the copy was short, and the
        # first read of it raised. The raised path names no repository file at all, so both rules
        # above miss it -- which is why it sat in DEAD while the script was, in fact, looking at
        # the wrong tree the whole time.
        if "FileNotFoundError" in text and any(s in text for s in SCRATCH):
            return "WRONG-ROOT", ("raised inside its own scratch tree, so the copy it made was "
                                  "empty: it was reading a tree that was not there")
        return "DEAD", f"found the root, then failed for another reason (rc={rc})"
    # rc=0 IS NOT A PASS, AND THIS IS THE ROW THAT MATTERS MOST. A script that resolved
    # against the wrong root and then had nothing to complain about exits 0 having measured
    # NOTHING: `classify.sh` printed 3476 rows, every one NOREF, and reported success; that is
    # the same defect as a green gate that ran no lane, and it is the reason the planted
    # root assertions in these shims exist. So a zero is SUSPECT whenever the run complained
    # about anything, and only RAN when it complained about nothing at all.
    if any(c in text for c in COMPLAINTS):
        return "SUSPECT", "exited 0 but complained; read the evidence -- a wrong root can exit 0"
    return "RAN", "reached its own work with rc=0 and nothing complained"


def main(argv: list[str]) -> int:
    tree, *runs = argv[1:]
    grand: dict[str, int] = {}
    for name in runs:
        run = pathlib.Path(name)
        print(f"\n=== {name}")
        print(f"{'script':<24} {'rc':>4}  {'verdict':<11} evidence")
        tally: dict[str, int] = {}          # per run; a cumulative total across two runs
        for row in sorted(run.glob("*.rc")):  # one row per EXECUTED script, so a script the
            script = row.name[:-3]           # harness skipped has no row and is not counted
            rc = int(row.read_text().strip())
            verdict, why = classify(tree, run, script, rc)
            tally[verdict] = tally.get(verdict, 0) + 1
            grand[verdict] = grand.get(verdict, 0) + 1
            print(f"{script:<24} {rc:>4}  {verdict:<11} {why}")
        counted = sum(tally.values())
        print(f"--- executed {counted} of 18; " + "  ".join(f"{k}={v}" for k, v in sorted(tally.items())))
    print("\n=== both runs, for reference only -- a verdict is a property of ONE tree")
    print("    " + "  ".join(f"{k}={v}" for k, v in sorted(grand.items())))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))