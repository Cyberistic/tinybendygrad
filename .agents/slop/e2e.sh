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
cd "$(dirname "$0")/../.." || exit 2
exec .venv/bin/python checks/e2e.py "$@"