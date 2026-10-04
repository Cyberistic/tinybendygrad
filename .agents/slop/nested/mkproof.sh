#!/bin/sh
# .agents/slop/nested/mkproof.sh -- MAKE A PROOF COPY THAT COMPILES, OR REFUSE.
#
#   sh .agents/slop/nested/mkproof.sh <workdir>
#
# WHY THIS EXISTS, AND IT IS NOT MY FIX.  At 18:38 a concurrent agent left
# `tinybendygrad/helpers.bend` at ZERO BYTES for over three minutes, and
# `tinybendygrad/uop/ops.bend` is currently 287047 bytes while `uop/symbolic.bend`
# calls `O.ParamArg.no_slot`, a def that only the 400159-byte parent revision has.
# Neither file is this unit's to edit, so the reader is LOCAL: the whole of
# `tinybendygrad` is COPIED (`.bend` imports are RELATIVE) and `bin`, `references`,
# `tinygrad` and `.venv` are symlinked, exactly as
# `.agents/slop/e2e_port/run-port-mm.sh:mkcopy` does it.
#
# It then adds EXACTLY the two missing defs to the COPY's `uop/ops.bend`, text taken
# from the parent revision, and NOTHING else.  Every claim this unit makes is about
# `runtime/ops_python.bend`, which is copied verbatim from the live tree.
#
# MARKED AS A WORKAROUND TO BE FLIPPED BACK, NOT A DESIGN.  When the substrate
# settles, re-run the same gate against the live tree and this script goes unused.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
W=${1:-${TMPDIR}/nested-proof}
rm -rf "$W"
mkdir -p "$W/.agents/slop"
cp -R "$ROOT/tinybendygrad" "$W/tinybendygrad"
cp -R "$ROOT/.agents/slop/nested" "$W/.agents/slop/nested"
ln -s "$ROOT/bin" "$W/bin"; ln -s "$ROOT/references" "$W/references"
ln -s "$ROOT/tinygrad" "$W/tinygrad"; ln -s "$ROOT/.venv" "$W/.venv"

OPS="$W/tinybendygrad/uop/ops.bend"
if ! grep -q "def ParamArg.no_slot" "$OPS"; then
  "$ROOT/.venv/bin/python" - "$OPS" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
anchor = "def ParamArg.dtype(x: ParamArg) -> S.Dt:"
add = ("# ADDED BY .agents/slop/nested/mkproof.sh -- SUBSTRATE ONLY, NOT A DESIGN.\n"
       "# `uop/symbolic.bend` calls `O.ParamArg.no_slot` and this revision does not\n"
       "# define it.  Text taken verbatim from the parent revision `@-`.\n"
       "def ParamArg.no_slot() -> U32: 4294967295\n\n"
       "def ParamArg.has_slot(x: ParamArg) -> Bool:\n"
       "  Bool.not(U32.is_eq(ParamArg.slot(x), ParamArg.no_slot()))\n\n")
assert s.count(anchor) == 1, s.count(anchor)
p.write_text(s.replace(anchor, add + anchor))
print("mkproof: added ParamArg.no_slot/has_slot to the COPY's uop/ops.bend")
PY
fi
echo "mkproof: $W"
