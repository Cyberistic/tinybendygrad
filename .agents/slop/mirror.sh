#!/bin/sh
# LOCAL READER for webgpu_call.bend, and a workaround to be flipped back.
#
# WHY IT EXISTS. `webgpu_call.bend` imports `runtime/ops_webgpu.bend`, which
# imports `../helpers.bend`. `helpers.bend` is owned by another agent and was
# observed MID-EDIT and uncompilable three times in a row:
#
#   tinybendygrad/helpers.bend:866  match Bool.or(k, m):
#     a parameter or field scrutinee (a match cannot scrutinize a computed value)
#
# Per `.agents/slop/agent-core.md` the response to a cold-compile failure naming a
# def that is not in your file is to SAY SO and use a local reader rather than
# editing their file. This is that reader. It mirrors
# `tinybendygrad/{helpers.bend,runtime/{ops_webgpu,webgpu_call}.bend}` into
# `.agents/slop/mirror/tinybendygrad/...`, so `../helpers.bend` still resolves and
# the check is unaffected by the other agent's in-flight edit.
#
# NOT A DESIGN. When `tinybendygrad/helpers.bend` compiles again, delete this and
# run `tinybendygrad/runtime/webgpu_call.bend` directly. `mirror_check.sh` says
# whether that is possible yet.
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
M="$ROOT/.agents/slop/mirror/tinybendygrad"
mkdir -p "$M/runtime"
# By default the mirror uses `.agents/slop/helpers.frozen.bend`, a snapshot of
# `tinybendygrad/helpers.bend` taken from jj revision `ovrmvomtslkz` -- the last
# revision at which `ops_webgpu.bend` printed all 147 rows. `helpers.bend` was
# then observed uncompilable for 2+ consecutive minutes by another agent, which
# is what the freeze is for. Set LIVE=1 to mirror the working copy instead.
if [ "${LIVE:-0}" = "1" ]; then cp "$ROOT/tinybendygrad/helpers.bend" "$M/helpers.bend";
else cp "$ROOT/.agents/slop/helpers.frozen.bend" "$M/helpers.bend"; fi
cp "$ROOT/tinybendygrad/runtime/ops_webgpu.bend" "$M/runtime/ops_webgpu.bend"
cp "$ROOT/tinybendygrad/runtime/webgpu_call.bend" "$M/runtime/webgpu_call.bend"
echo "$M"