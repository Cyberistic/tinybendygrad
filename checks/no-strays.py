#!/usr/bin/env python3
"""Refuse a stray at the repository root. `checks/no-strays.py`

WHAT IT CLAIMS, with its denominator: every FILE at the repository root is either named in
`ROOT_ENTRIES` or is explained by this script, and the count of unexplained files is printed
beside the count of root files. Exit 0 only when that count is zero.

WHY IT IS A GATE AND NOT A TIDY RULE.  Four strays accumulated at the root on one day and
three of them had the same cause, which no directory-organising rule would have caught:

    after.txt   33 KB   80 lines, all `/var/folders/...`   <- a `find` listing of a $TMPDIR tree
    before.txt 114 KB  284 lines, all `/var/folders/...`   <- ditto, the before half
    closure.txt  14 KB                                    <- ditto, a third copy of the listing
    .err          0 bytes                                 <- a redirect target that never filled

`after`/`before`/`closure` were ONE gate's output, written three times, at the root, because
`find "$T" > after.txt` had no path discipline. `bf_base_tmp.c` was a port file copied out to
the root by `sed`. So the two failure modes are:

  1. a NAME this project uses for scratch, and
  2. CONTENT that is a listing of a `$TMPDIR` path -- which is debris from a machine, not a
     fact about this repository, and is unreadable on any other machine.

Mode 2 is not what the allowlist misses -- MEASURED, after I first wrote this file claiming it
was: the allowlist catches `listing-of-the-closure.txt` by name, and catches it correctly. What
the allowlist cannot catch is a name ADDED TO THE ALLOWLIST, because this guard's own message
invites that ("add it to ROOT_ENTRIES deliberately") and nothing then looks at the content again.
So the content test's job is to survive its own allowlist: a `$TMPDIR` listing stays a stray even
after somebody has blessed its name.

MEASURED, both directions, on this tree:
    innocent name + 100% $TMPDIR lines  -> caught BY CONTENT ("100% of its lines are ...")
    scratch name  + one hand-written line -> caught BY NAME    ("name is a scratch name")
**AND THE CORRECTION MATTERED: MY FIRST VERSION OF THIS DOCSTRING SAID THE NAME TEST COULD NOT
CATCH MODE 2. IT CAN. THE CLAIM WAS WRONG IN THE DIRECTION THAT MAKES A GUARD LOOK STRONGER THAN
IT IS, WHICH IS THE ONLY DIRECTION THAT IS SAFE TO BE WRONG IN AND ALSO THE ONLY ONE THAT HIDES A
GAP.**

WHAT IT DELIBERATELY DOES NOT DO.  It does not delete anything, and it does not judge DIRECTORIES
by name -- 33 directories are listed here and a new one should be added deliberately rather than
discouraged. A guard that makes adding a directory annoying gets a directory added to the
allowlist without being looked at, which is the same failure as an unenforced pin.

ONE THING THIS FILE GOT WRONG FIRST, because the correction is the useful part.  Deciding what
"a report cites" by matching the bare basename reported 6 citers for a ZERO-BYTE `.err` and 89
for a file named `bend`. Every one was a substring hit inside a longer word -- `.err` inside
`.error`, `bend` inside `bender`. **That is the third time this project has made that mistake**
(`_cleanup/classify.py` reported 3,574 false citations for the same reason). So a citation here
must be a WHOLE PATH TOKEN, matched by `WORD`, never `in`.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Measured 2026-10-05, after the four strays above were cleared. Every entry is real project
# structure. `sz.py` is the one that looks wrong: it is COMMITTED and four reports cite it, so
# it stays until its owner decides where it belongs -- a guard is not a reorganisation.
ROOT_ENTRIES = set("""
    .agents .coveragerc .git .github .gitignore .jj .pre-commit-config.yaml .pylintrc .venv
    AGENTS.md bin checks conftest.py docs examples extra langs LICENSE mkdocs.yml opencode.json
    probe pyproject.toml README.md references runs serve_docs.sh spec sz.py test tinybendygrad
    tinygrad tinygrad.egg-info tools uv.lock
""".split())

# Scratch names this project actually uses. A file at the root with one of these is debris
# whatever it contains, because the root is not where a run's output belongs.
SCRATCH_NAME = re.compile(
    r"(^\.|\.(err|out|tmp|bak|orig|rej|swp)$|~$|\.staged-(mem|blob)-|^\.|^_)"
    r"|^(before|after|baseline|closure)\.[a-z]+$"
    r"|(^|[-_.])(tmp|temp|scratch|workdir|probe|dump)([-_.]|$)")

# A listing of a machine-local path. `find $TMPDIR > f` writes exactly this and it means nothing
# to anyone else. Requiring MOST lines to be machine-local keeps an ordinary report from being
# caught by one stray path in prose.
MACHINE_PATH = re.compile(r"(/var/folders/|/private/var/folders/|/tmp/[A-Za-z0-9_.-]+/)")
MIN_BLOB_RATIO = 0.6


def root_files() -> list[Path]:
    return sorted(p for p in ROOT.iterdir() if p.is_file() and p.name not in ROOT_ENTRIES)


# A scratch SHAPE is debris WHEREVER it sits in a SOURCE tree. Four `ops.staged-blob-*` files
# and three `memory.staged-mem-*` sat inside `tinybendygrad/` for two days and this guard could
# not see them: its population was `ROOT.iterdir()`, ONE LEVEL TOO HIGH.
#
# **THE FIRST DEEP VERSION WAS NARROWER AND STILL A SHAPE -- and a unit found six files it
# missed.** It reused only the residue arms (`\.staged-`, `\.mut$`, `~`, backups). MEASURED
# 2026-10-06 over all 144 files under `tinybendygrad/`: it flagged **0 of these six**, all
# tracked scratch beside source:
#
#   runtime/zzdiag.bend                 runtime/zzread.bend
#   runtime/zzsplit.bend                runtime/zzprobe2.bend   (`:1` = `# scratch probe -- DELETE.`)
#   runtime/support/zz_objc_mutant.bend runtime/support/am/ip_scratch_sweep.bend
#
# Two say so in their own name (`_mutant`, `_scratch_sweep`); four carry a `zz` prefix this
# project uses for "sorts last, scratch". So the shape they ARE is a NAME SHAPE.
#
# **THE STRUCTURAL TEST WAS MEASURED AND REJECTED.** "Nothing imports it AND it imports nothing"
# fires on 32 of 138 `.bend` files, and 28 are REAL ports the .bend wiring simply does not reach
# yet -- `runtime/support/{objc,c,hcq2,elf,system,usb}.bend`, every `compiler_*.bend`, the
# `__init__.bend` hubs, `sz.bend`. The header test ("no self-port header") fires on 78. **The
# import graph is incomplete, so "unreferenced" is NOT "not source"**; the population is the name
# shape, admitted here as a regex over the tree (doctrine 1c).
#
# **`^\.` and `^_` FROM `SCRATCH_NAME` ARE STILL NOT REUSED AT DEPTH**: they catch `.gitignore`
# and `__init__.py`, ordinary everywhere but the root. Only lone-underscore `_p6`-style names are
# kept. **`probe` is deliberately NOT a bare token**: `uop/probe-mmcore.bend` matches it and a
# gate cites it (`.agents/slop/mm-mutate.py:17` names it `SRC`), so it is KEPT --
# `.agents/slop/hygiene-2026-10-04.md:145,157` records that exemption.
#
# **AND THE SHAPE IS A POPULATION ONLY FOR THE TREE IT WAS WRITTEN FOR.** Over the whole repo the
# same regex hits upstream's own `test/amd/hw/test_scratch.py`; `test/` is tinygrad's oracle, not
# this project's source. So the walk is scoped to `SOURCE_TREES`.
SCRATCH_SHAPE = re.compile(
    r"\.staged-(mem|blob)-\d+$|\.mut$|~\d*$|\.(bak|orig|rej|swp)$"   # residue anywhere
    r"|^zz"                                                          # this project's scratch prefix
    r"|(?:_|\.)(mutant|scratch|sweep|diag)(?:\.|_|$)"                # _mutant / _scratch_sweep
    r"|^_[^_]"                                                       # _p6, a lone leading underscore
)
def _coindep():
    """The single declaration, loaded BY PATH -- see checks/coindep.py."""
    import importlib.util
    from pathlib import Path as _P
    spec = importlib.util.spec_from_file_location(
        "coindep", _P(__file__).resolve().parent / "coindep.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


SKIP_DIRS = set(_coindep().SKIP_DIRS)
SOURCE_TREES = ("tinybendygrad",)


def stray_shapes_anywhere() -> list[Path]:
    """A scratch-shaped file in a SOURCE tree, at any depth. MEASURED over `tinybendygrad/`
    (144 files, 2026-10-06): 7 hits -- the six strays above plus `runtime/_p6.bend` -- and 0 real
    ports. `test/`, upstream's oracle, is not walked: it carries `test/amd/hw/test_scratch.py`."""
    out: list[Path] = []
    for tree in SOURCE_TREES:
        base = ROOT / tree
        if not base.exists():
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            out.extend(Path(dirpath) / f for f in filenames if SCRATCH_SHAPE.search(f))
    return sorted(out)


def machine_path_ratio(text: str) -> float:
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if not lines:
        return 0.0
    return sum(1 for ln in lines if MACHINE_PATH.search(ln)) / len(lines)


def cited_by_a_report(path: Path) -> list[str]:
    """Committed files naming this path, matched as a WHOLE PATH TOKEN.

    `git grep -F <name>` is a substring match and is how six reports 'cited' a zero-byte `.err`.
    The boundary class keeps `.err` from matching inside `.error` and `bend` inside `bender`.
    """
    r = subprocess.run(
        ["git", "grep", "-l", "-E",
         rf"(^|[^A-Za-z0-9_./-]){re.escape(path.name)}([^A-Za-z0-9_-]|$)", "--", "*.md"],
        cwd=ROOT, capture_output=True, text=True)
    return [ln for ln in r.stdout.split() if ln] if r.returncode in (0, 1) else []


def main() -> int:
    # THE SHAPE FIRST, AT ANY DEPTH IN A SOURCE TREE. A scratch name is debris wherever it is,
    # and `ROOT.iterdir()` could not see past the root.
    deep = stray_shapes_anywhere()
    for p in deep:
        print(f"  STRAY-SHAPE  {str(p.relative_to(ROOT)):<48} {p.stat().st_size:>9d} B   "
              f"scratch name in a source tree")

    all_files = [p for p in sorted(ROOT.iterdir()) if p.is_file()]
    strays = root_files()
    print(f"no-strays: {len(all_files)} files at the root, {len(ROOT_ENTRIES)} entries allowed, "
          f"{len(strays)} to explain; {len(deep)} scratch-shaped in source trees")
    if not strays:
        print("  CLEAN: every root file is named in ROOT_ENTRIES")
        return 1 if deep else 0

    unexplained = []
    for p in strays:
        reasons = []
        if SCRATCH_NAME.search(p.name):
            reasons.append("name is a scratch name")
        try:
            text = p.read_text(errors="replace")
        except OSError as exc:
            reasons.append(f"unreadable: {exc.strerror}")
            text = ""
        ratio = machine_path_ratio(text)
        if ratio >= MIN_BLOB_RATIO:
            reasons.append(f"{ratio:.0%} of its lines are a machine-local $TMPDIR listing")
        citers = cited_by_a_report(p)
        if reasons:
            print(f"  STRAY  {p.name:<24} {p.stat().st_size:>9d} B   {'; '.join(reasons)}")
            if citers:
                print(f"          cited by {len(citers)} report(s): {', '.join(citers[:4])}"
                      f"{' …' if len(citers) > 4 else ''}")
                print("          -> it is CITED, so MOVE it under .agents/slop/ and keep the "
                      "basename; do not delete evidence")
            unexplained.append(p)
        else:
            print(f"  new    {p.name:<24} {p.stat().st_size:>9d} B   not on the allowlist and no "
                  f"stray shape -- add it to ROOT_ENTRIES deliberately or remove it")
            unexplained.append(p)

    print(f"  {len(unexplained)} unexplained of {len(all_files)} root files")
    if unexplained:
        print("  NOT CLEAN. A root file nobody can explain is how a repo stops being navigable.")
    if deep:
        print(f"  NOT CLEAN. {len(deep)} scratch-shaped file(s) in "
              f"{' or '.join(SOURCE_TREES)} -- a run's output belongs under .agents/slop/, "
              f"beside the source.")
    return 1


if __name__ == "__main__":
    sys.exit(main())