#!/bin/sh
# wt-sync.sh -- mirror tinybendygrad/ into the WORKAROUND tree, then restore
# helpers.bend from the LAST COMMIT.
#
# WHY THIS EXISTS, and it is a COMPILER WORKAROUND, NOT A DESIGN. A live agent is
# mid-edit on `tinybendygrad/helpers.bend` and it does not compile: eight `nc_*`
# defs read an un-`+`-pinned binder twice, so `./bin/bend` fails on EVERY file in
# the tree (measured: `uop/ops.bend`, `codegen/rewriter.bend`, `uop/render.bend`
# -- all the same error, none of them mine). `agent-core.md` says to report that
# rather than edit their file, so this script syncs the tree and puts the LAST
# COMMITTED helpers.bend back, which is the substrate the 109-row baseline was
# measured against.
#
# FLIP BACK as soon as that agent lands: delete this script and the tree.
set -eu
# ROOT: one level up from `checks/`, and ASSERTED. See `.agents/slop/shells/README.md`.
_d=${0%/*}; case $_d in "$0") _d=.;; esac
cd "$_d/.." || exit 2
[ -f pyproject.toml ] && [ -d tinybendygrad ] || { echo "$0: not at the repo root (pwd $PWD)" >&2; exit 2; }
R=$PWD
W="$R/.agents/slop/xd1/wt"
rm -rf "$W/tinybendygrad"
cp -R "$R/tinybendygrad" "$W/"
git -C "$R" show HEAD:tinybendygrad/helpers.bend > "$W/tinybendygrad/helpers.bend"
echo "# workaround tree at $W (helpers.bend from HEAD, everything else live)"