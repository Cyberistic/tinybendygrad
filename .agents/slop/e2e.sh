#!/bin/sh
# SHIM. The gate moved to `checks/e2e.py` (`.venv/bin/python checks/e2e.py --help` says what it
# gates and each verdict's DENOMINATOR). This file keeps the path the gate's own header advertises
# -- ".agents/slop/e2e.sh -- THE ONE COMMAND" -- working.
#
# THE SHELL BODY IS NOT DELETED, IT IS FROZEN: `.agents/slop/e2epy/oracle-e2e.sh`, still RUNNABLE,
# and pinned by sha256 in `checks/e2e.py` ORACLE_PIN, which is CHECKED IN CODE on every run and
# refuses with exit 3 on drift. The rule the port had to satisfy is that the Python reproduces the
# shell's verdict on EVERY INPUT -- which is only checkable while the shell still exists.
#
# `E2E_ROOT` is the oracle copy's only edit, so a copy that must run against a FIXTURE tree rather
# than the live repository can be pointed somewhere else. `checks/e2e.py` honours the same variable.
# `env -u PYTHONPATH` IS DELIBERATELY ABSENT: the shell never applied it, so the eight stages
# inherit the caller's PYTHONPATH, and stripping it here would change what `e2e_mm.py` can import --
# a change to a verdict, in the one direction this migration may not move.
# `dirname` is an EXTERNAL COMMAND for something the shell can do itself, and a shim whose
# preamble depends on PATH reports "command not found" and then tries to exec a relative
# path from the wrong place. MEASURED with dirname off PATH: e2e.sh exits 126, this exits
# 127 -- both LOUDLY, so the severity is not "green having run nothing"; but neither needs
# the dependency. `${0%/*}` is POSIX and spawns nothing, and the `[ "$d" = "$0" ]` arm is
# the case where $0 has no slash at all.
_d=${0%/*}; [ "$_d" = "$0" ] && _d=.
cd "$_d/../.." || exit 2
exec .venv/bin/python checks/e2e.py "$@"