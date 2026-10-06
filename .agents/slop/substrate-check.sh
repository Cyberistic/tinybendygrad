#!/bin/sh
# SHIM. The gate moved to `checks/substrate.py` (`.venv/bin/python checks/substrate.py --help`
# says what it gates and what its denominators are). This file stays so every existing invocation
# path keeps working.
#
# THE SHELL BODY IS NOT DELETED, IT IS FROZEN: `.agents/slop/substrate/oracle-check.sh` is the
# pre-port script (sha256 6d1000712f0f…600e) and is still RUNNABLE, because the rule the port had
# to satisfy was that the Python reproduces the shell's verdict on every input -- which is only
# checkable while the shell exists. Run it with
#     SUBSTRATE_REPO=$PWD zsh .agents/slop/substrate/oracle-check.sh <files...>
# `SUBSTRATE_REPO` is the oracle copy's only edit, and the pin lives IN CODE in
# `checks/substrate.py`, not in a comment.
#
# WHY `env -u PYTHONPATH`: contamination is real in this tree and `checks/differ.py` measures it
# contaminating a control.
#
# WHAT MOVED AND WHAT DID NOT: the shell's `perl -e 'alarm 300; exec @ARGV'` bounded TIME only,
# and two unbounded `bend` processes took this machine's memory to zero on 2026-10-05. The Python
# runs every instrument under BOTH bounds, one `bend` at a time, and reports a kill on stderr.
# `dirname` is an EXTERNAL COMMAND for something the shell can do itself, and a shim whose
# preamble depends on PATH reports "command not found" and then tries to exec a relative
# path from the wrong place. MEASURED with dirname off PATH: e2e.sh exits 126, this exits
# 127 -- both LOUDLY, so the severity is not "green having run nothing"; but neither needs
# the dependency. `${0%/*}` is POSIX and spawns nothing, and the `[ "$d" = "$0" ]` arm is
# the case where $0 has no slash at all.
_d=${0%/*}; [ "$_d" = "$0" ] && _d=.
cd "$_d/../.." || exit 2
exec env -u PYTHONPATH .venv/bin/python checks/substrate.py "$@"