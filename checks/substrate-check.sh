#!/bin/sh
# SHIM. The gate moved to `checks/substrate.py` (`.venv/bin/python checks/substrate.py --help`
# says what it gates and what its denominators are). This file stays so every existing invocation
# path keeps working.
#
# IT WAS DELETED ONCE WHILE THIS UNIT WORKED (2026-10-05 ~15:20, by something outside this unit's
# tree), and it is restored here because "every existing invocation path keeps working" is a claim
# and this file is one of those paths. `.agents/slop/substrate-check.sh` is the twin and carries
# the same body; `COLDNESS.md` §8 and `checks/disarm.sh` invoke THAT one.
#
# THE SHELL BODY IS NOT DELETED, IT IS FROZEN: `.agents/slop/substrate/oracle-check.sh` is the
# pre-port script (sha256 6d1000712f0f…600e), still `+x`, still runnable, and pinned by sha256 in
# `checks/substrate.py` ORACLE_PIN -- checked IN CODE on every run, not in a comment. Its only
# edit is a `SUBSTRATE_REPO` default in its `cd`, so the copy can be run from anywhere:
#     SUBSTRATE_REPO=$PWD zsh .agents/slop/substrate/oracle-check.sh <files...>
#
# WHY `env -u PYTHONPATH`: contamination is real in this tree and `checks/differ.py` measures it
# contaminating a control.
#
# WHAT MOVED AND WHAT DID NOT: the shell's `perl -e 'alarm 300; exec @ARGV'` bounded TIME and
# nothing else, and two unbounded `bend` processes took this machine's memory to zero on
# 2026-10-05. The Python runs every instrument under BOTH bounds, one `bend` at a time, and
# reports a kill on stderr so the verdict line stays the shell's byte for byte.
# `dirname` is an EXTERNAL COMMAND for something the shell can do itself, and a shim whose
# preamble depends on PATH reports "command not found" and then tries to exec a relative
# path from the wrong place. MEASURED with dirname off PATH: e2e.sh exits 126, this exits
# 127 -- both LOUDLY, so the severity is not "green having run nothing"; but neither needs
# the dependency. `${0%/*}` is POSIX and spawns nothing, and the `case` arm is the case
# where $0 has no slash at all.  `case` rather than `[ .. ] && ..` because that AND-list
# returns 1 when the test fails, which is fatal under `set -e` in a sibling shim.
#
# THE DEPTH IS `..`, NOT `../..`, AND THE SECOND ONE WAS A MEASURED 127.  This file is in
# `checks/`, which is ONE level below the root, so `$_d/../..` is the PARENT OF THE REPO:
# every relative path below then named a file that does not exist and the script exited
# 127.  The comment above it used to say `dirname` off PATH gives 126 and *this* 127 --
# two different exit codes for the same missing-preamble mistake, both LOUD, and the
# louder one was hiding a wrong root behind an unrelated PATH story.
_d=${0%/*}; case $_d in "$0") _d=.;; esac
cd "$_d/.." || exit 2
# AND THE ROOT IS ASSERTED, NOT ASSUMED.  `cd` does not care where it lands, so a
# one-character depth slip is silent until something downstream fails for a reason that
# has nothing to do with depth.  Two tracked markers that exist at the root and nowhere
# else: a clone has both, and a stray parent directory has neither.
[ -f pyproject.toml ] && [ -d tinybendygrad ] ||
  { echo "$0: not at the repo root (pwd $(pwd))" >&2; exit 3; }
exec env -u PYTHONPATH .venv/bin/python checks/substrate.py "$@"
