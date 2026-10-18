#!/bin/sh
# verify.sh -- ONE file, ONE bend, under the memory watchdog. Reports rc, the TOKEN
# (never `$?` -- `checks/bounded.py` says so in its own header), peak RSS, and the
# ERROR COUNT, which is the number the shape choice turns on.
#
# usage: verify.sh FILE TAG
set -u
F="$1"; T="$2"
SPEC=1 DEV=CPU .venv/bin/python checks/bounded.py --seconds 900 --mb 2048 -- \
  ./bin/bend "$F" --check-only > ".agents/slop/arenaparam/$T.out" 2> ".agents/slop/arenaparam/$T.err"
TOK=$(awk '/^\[bounded\]/{print $2}' ".agents/slop/arenaparam/$T.err")
RSS=$(sed -n 's/.*peak-RSS=\([0-9]*\) MB.*/\1/p' ".agents/slop/arenaparam/$T.err" | head -1)
ERRS=$(grep -c -E '^Error|^ *Error:' ".agents/slop/arenaparam/$T.err")
ERRS2=$(grep -c -i 'error' ".agents/slop/arenaparam/$T.err")
printf '%s\tTOKEN=%s\tpeakRSS=%sMB\terrLines=%s\terrAny=%s\n' "$F" "$TOK" "${RSS:-?}" "$ERRS" "$ERRS2"