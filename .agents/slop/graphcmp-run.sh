#!/bin/sh
# SHIM. The driver moved to `checks/differ.py run` (`.venv/bin/python checks/differ.py --help`
# says what it gates). This file stays so every existing invocation path keeps working.
#
# THE SHELL BODY IS NOT DELETED, IT IS FROZEN: `.agents/slop/diffpy/oracle-run.sh` is the
# pre-port script verbatim (sha256 636eb200c34d…3365) and is still RUNNABLE, because the rule
# the port had to satisfy was that the Python reproduces the shell's verdict on every input --
# which is only checkable while the shell exists. `GCMP_REPO` is the oracle copy's only edit.
cd "$(dirname "$0")/../.." || exit 2
exec .venv/bin/python checks/differ.py run "$@"
