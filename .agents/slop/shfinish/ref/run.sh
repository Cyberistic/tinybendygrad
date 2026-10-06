#!/bin/sh
# Run a gate and record VERDICT + EXIT STATUS + WHOLE OUTPUT, so two implementations can be diffed
# on all three and not on the one line that happens to say PASS.  $1=label, rest = argv.
L=$1; shift
D=$(cd "$(dirname "$0")" && pwd)
( /usr/bin/time -l "$@" > "$D/$L.out" 2> "$D/$L.err"; echo "EXIT=$?" >> "$D/$L.out" ) &
P=$!
( sleep 900; kill -9 $P 2>/dev/null ) >/dev/null 2>&1 &
wait $P
