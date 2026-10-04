#!/bin/sh
# ops501-atrest.sh -- run the AT-REST (`@-`) revision of tinybendygrad/uop/ops.bend and
# print its `s5_` rows, WITHOUT touching the live tree.
#
#   sh .agents/slop/ops501-atrest.sh > .agents/slop/oracles/ops501-atrest.txt
#
# WHY IT EXISTS. `jj file show -r @` reads the WORKING COPY, so `@` and `@-` look
# identical if you only ask `@` -- and that is how "red at rest" got reported as
# green. The live `ops.bend` is being edited by another unit right now, so the
# at-rest state CANNOT be measured from the live path at all.
#
# WHY IT IS NOT A $TMPDIR COPY. `ops.bend:166-168` imports `./../helpers.bend` and
# `./../LAWS/spec.bend`; a copy outside `tinybendygrad/uop/` cannot resolve them and
# prints a phantom 0 rows (agent-core.md's `$TMPDIR` trap). So the revision is
# materialised IN PLACE, at the same relative path with a different filename, and
# DELETED in a trap -- additive, so no live file is ever written.
#
# THE STAGING PATH IS GITIGNORED (`tinybendygrad/**/*ATREST-*.bend`), and it has to
# be. An in-place stage is unavoidably inside the source tree, and an unignored one
# is two traps at once: a concurrent `for f in tinybendygrad/uop/*.bend` sweep counts
# it as a port and reports it RED when the RED is the OLD revision, and one careless
# `jj split` commits a whole stale ops.bend. Matches 0 real files, by construction.
set -e
cd "$(dirname "$0")/../.."

REV=${1:-@-}
STAGE=tinybendygrad/uop/ops-ATREST-$$.bend

trap 'rm -f "$STAGE"' EXIT INT TERM

jj file show -r "$REV" tinybendygrad/uop/ops.bend > "$STAGE"
# assert the staged revision IS the revision, not a truncated pipe
expect=$(jj file show -r "$REV" tinybendygrad/uop/ops.bend | md5 -q)
got=$(md5 -q "$STAGE")
if [ "$expect" != "$got" ]; then
  echo "ops501-atrest: staged digest $got != revision digest $expect" >&2
  exit 1
fi

./bin/bend "$STAGE" | grep '^s5_'