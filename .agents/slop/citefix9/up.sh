#!/bin/sh
# up.sh PATH [LO [HI]] -- print upstream lines at the PIN
P=$(git log -1 --format=%H refs/remotes/upstream/master -- tinygrad/)
if [ -n "$2" ]; then git show "$P:$1" | sed -n "$2,$3p" | cat -n | sed "s/^/  /"; else git show "$P:$1" | cat -n; fi
