#!/bin/zsh
# THE DEMONSTRATION, AS A REPEATABLE ARTIFACT. Writes nothing to the repo except the
# one probe it plants and removes inside a single guarded step.
#
# ⚠ DO NOT EDIT substrate-check.sh WHILE A RUN IS IN FLIGHT. zsh READS A SCRIPT
# INCREMENTALLY, so an edit made mid-run resumes at a stale byte offset and reports
# `substrate-check.sh:309: parse error near ()'` -- half a verdict, and it looks like a
# result. MEASURED 2026-10-05: a 138-file run that was edited under itself produced 141
# lines, a correct `ROUTE`, and then died, so its COLD count was never cross-checked.
# Same species as `agent-core.md`'s "verify an instrument before believing its output".
#
# `-n` = HALF 2 ONLY, which SKIPS the ~minutes of `bend --check-only` verdicts and keeps
# the `PROVENANCE` block, because that block reads `git ls-files` and the filesystem and
# does not need a verdict. **The split is a pre-gate**: you learn a probe is in the tree
# in 2.4 s, before spending ten minutes finding out whether the port still compiles.
# ROOT: one level up from `checks/`, and ASSERTED. See `.agents/slop/shells/README.md`.
_d=${0%/*}; case $_d in "$0") _d=.;; esac
cd "$_d/.." || exit 2
[ -f pyproject.toml ] && [ -d tinybendygrad ] || { echo "$0: not at the repo root (pwd $PWD)" >&2; exit 3; }
CHECK=.agents/slop/substrate-check.sh
PLANT=tinybendygrad/runtime/PROBE-SELFDEMO.bend
say() { print -r -- "$1"; }
# ⚠ THE LIST IS RE-DERIVED EVERY TIME, AND THE FIRST CUT SNAPSHOT IT ONCE -- WHICH MADE
# THE WHOLE DEMONSTRATION VACUOUS. Four consecutive passes printed IDENTICAL numbers,
# `of 138` four times, because a file list frozen before the probe was planted never
# contains the probe. **A STALE FILE LIST IS A WAY TO MAKE A DENOMINATOR LIE, and it is
# silent**: the instrument is correct, the input is wrong, and both look like a pass.
# `.agents/slop/triage/allfiles.txt` is exactly such a list -- frozen 2026-10-04 22:34 --
# so a reader comparing a router run against it is comparing against a census, not a tree.
split() { "$CHECK" -n $(find tinybendygrad -name '*.bend' | sort) 2>&1 \
            | grep -E '^(PROVENANCE|PORT ALARM|DENOMINATOR)'; }

say "### A. AS IT STANDS -- the live tree, every .bend it holds"
split

say ""
say "### B. A PROBE WITH AN INNOCENT NAME, PLANTED IN THE LIVE TREE"
say "    (neither *.mut.bend nor probe-*.bend: nothing to remember, nothing to match, and"
say "     it COMPILES, so it cannot be waved off as broken debris)"
printf 'import Base\n\ndef main() -> IO(Unit):\n  IO.print("probe")\n' > "$PLANT"
split

say ""
say "### C. THE SAME FILE REMOVED -- the split returns to A"
rm -f "$PLANT"
split

say ""
say "### D. THE PLANT THIS UNIT OWNS DELETED: runtime/ops_bend.mut.bend (md5 9bdb1dd8...)"
rm -f tinybendygrad/runtime/ops_bend.mut.bend
split

say ""
say "### E. STATE"
print -r -- "PROBE-SELFDEMO leftover? $([ -e "$PLANT" ] && echo YES-LEFTOVER || echo no)"
print -r -- "ops_bend.mut.bend       ? $([ -e tinybendygrad/runtime/ops_bend.mut.bend ] && echo present || echo "deleted, by design")"
print -r -- "index untouched by this script? it never calls git"
rm -f "$LIST"