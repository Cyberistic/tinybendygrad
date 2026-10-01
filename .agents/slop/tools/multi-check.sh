#!/bin/sh
# Verify multi.bend against the COMMITTED fold.bend.
#
# WHY THIS EXISTS. `tinybendygrad/uop/fold.bend` is READ-ONLY to the
# schedule/multi agent, and another agent has an UNCOMMITTED edit in it that
# does not compile: fold.bend:1053 `const_i64.go`'s wildcard arm is
# `case _ _:` for a ONE-scrutinee `match`. That makes EVERY file importing
# `fold.bend` fail, including the committed-and-green `allreduce.bend`. It is
# REPORTED, NOT FIXED. This script copies the tree to a scratch dir, restores
# fold.bend from the last commit (where it checks), and runs both lanes there.
set -e
T=/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/mucheck
R=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
rm -rf "$T"; mkdir -p "$T"
rsync -a "$R/tinybendygrad/" "$T/"
(cd "$R" && jj file show -r @- tinybendygrad/uop/fold.bend) > "$T/uop/fold.bend"
cp "$R/tinybendygrad/schedule/multi.bend" "$T/schedule/multi.bend"
exec "$R/bin/bend" "$T/schedule/multi.bend" "$@"