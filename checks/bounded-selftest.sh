#!/bin/sh
# checks/bounded.py selftest -- A SHIM, and it used to be the cases.
#
# WHY A SHIM AND NOT A SECOND SUITE: every case here now lives in `checks/bounded.py --selftest`,
# beside the code it tests, in the same language, and it runs the guard by the same path a caller
# does (`sys.executable checks/bounded.py`). Two suites for one guard is how they drift, and this
# one had already drifted from its own subject: it ran `$G ... | tail -2` and read `$?` on the next
# line, which is the pipe-status trap (`$?` after a pipe is `tail`'s status) -- so its memory and
# timeout cases could not have failed.
#
# `perl` was also a dependency here and is not one any more: the bombs are `sys.executable`.
#
# Run: sh checks/bounded-selftest.sh
set -eu
cd "$(dirname "$0")/.."
exec .venv/bin/python checks/bounded.py --selftest
