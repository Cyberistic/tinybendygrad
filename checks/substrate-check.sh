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
# the dependency. `${0%/*}` is POSIX and spawns nothing, and the `[ "$d" = "$0" ]` arm is
# the case where $0 has no slash at all.
_d=${0%/*}; [ "$_d" = "$0" ] && _d=.
cd "$_d/../.." || exit 2
exec env -u PYTHONPATH .venv/bin/python checks/substrate.py "$@"
