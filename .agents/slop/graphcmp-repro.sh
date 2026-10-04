#!/bin/sh
# SHIM. The gate moved to `checks/differ.py repro [WAIT_MINUTES]`
# (`.venv/bin/python checks/differ.py --help` says what it gates). This file stays so every
# existing invocation path keeps working, and so the shell stays available as the ORACLE.
#
# THE SHELL BODY IS NOT DELETED, IT IS FROZEN: `.agents/slop/diffpy/oracle-repro.sh` is the
# pre-port script verbatim (sha256 a0cbb0f8796c…d2707) and is still RUNNABLE, so the port can
# be diffed against it; run it with `GCMP_RUN=.agents/slop/diffpy/oracle-run.sh` to make it
# drive the SHELL runner rather than this shim. Its only edits are `GCMP_REPO` (its `cd`) and
# `GCMP_RUN` (which runner it calls).
#
# THE WALL THIS SCRIPT EXISTS FOR, kept here because a shim is where a reader lands:
# `runs/graphcmp/D` is reproducible ONLY under a settled substrate. `--check-only` EXITS 1 on
# a clean file, so its FIRST LINE is the signal and never its status.
cd "$(dirname "$0")/../.." || exit 2
exec .venv/bin/python checks/differ.py repro "$@"
