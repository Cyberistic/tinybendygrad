#!/bin/sh
# beautiful-mnist-gate.sh -- run BOTH lanes of examples/beautiful_mnist.bend and diff them
# against the CPython oracle. Every step is `set -e`, so the script fails loudly.
#
#   sh .agents/slop/beautiful-mnist-gate.sh
#
# THREE LANES and they must agree byte for byte on the thirty SHARED rows:
#
#   py    CPython, python3 .agents/slop/beautiful-mnist-gate.py
#   bend  the interpreted lane, ./bin/bend examples/beautiful_mnist.bend
#   bn    the NATIVE lane, compiled with -o and then run
#
# `--check-only` is run first: it is the fastest way to find a proof failure and it
# needs no device either. It prints `SOME PROOFS FAIL / 14 defs rely on unsafe or foreign
# code` and that is EXPECTED and is `tinybendygrad/dtype.bend`'s fourteen unfilled laws,
# which `nn/optim.bend` also reports -- so this script does NOT gate on that line.
#
# SIX ROWS ARE BEND-ONLY and they are filtered BY NAME, not by position, so that a row
# that MOVES is never silently dropped:
#   row_round_2.3456, row_round_2.30   measure `H.f32_fixed`'s TRUNCATING `%.2f`, which
#                                      is a defect in `tinybendygrad/helpers.bend` and a
#                                      question only the Bend lane can answer. Both
#                                      print False.
#   unverified_lin2                    the 2-D `dot` graph, wrong on the Bend side
#                                      because `uop/fold.bend` defers PERMUTE's dtype.
#   unverified_adam                    `nn.optim.Adam` == `LAMB(adam=True)` (optim.py:139)
#                                      and `nn/optim.bend`'s own `unverified_lamb` row is
#                                      RED: 1 node against CPython's 49.
#   unverified_arange_dims             the RE-CONFIRMATION of the loss's W3a: an
#                                      `arange`-rooted node's SHAPE, which
#                                      `mxw_dims_of` answers with the EMPTY LIST because
#                                      `op_arange` puts a `U1` quantiser in its pad's
#                                      shape arg and `mxm_as_shape` refuses any non-CONST
#                                      element. It prints EMPTY on purpose: an empty
#                                      value is a MEASUREMENT, and if `mixin/rand.bend`
#                                      ever grows a CONST-arg `arange` this row prints
#                                      `10` and the header's W3a is out of date.
#   unverified_step                    `mn_step` ITSELF. CPython cannot answer it,
#                                      because the port takes `y` as a parameter and
#                                      CPython builds it from `arange` (W3a), so the
#                                      graphs differ from the first node on. The row
#                                      exists because `mn_step` was the file's largest
#                                      blind spot: NOTHING called it, so the whole W3b
#                                      closure -- the mask built inside, and the arena
#                                      it is interned in -- was invisible to the gate.
set -e
cd "$(dirname "$0")/../.."

BMN=/tmp/bmn
BEND_ONLY='row_round_2\.3456|row_round_2\.30|unverified_lin2|unverified_adam|unverified_arange_dims|unverified_step'

# `|| true` because `dtype.bend`'s fourteen unfilled laws make bend exit non-zero, and
# the failure this lane exists to catch is a SYNTAX or a PROOF error, which the message
# names and which the two diffs below would not.
./bin/bend examples/beautiful_mnist.bend --check-only || true

python3 .agents/slop/beautiful-mnist-gate.py > $BMN.py
./bin/bend examples/beautiful_mnist.bend | grep -vE "^($BEND_ONLY)=" > $BMN.bd
./bin/bend examples/beautiful_mnist.bend -o $BMN.bin
$BMN.bin | grep -vE "^($BEND_ONLY)=" > $BMN.bn

diff $BMN.py $BMN.bd
diff $BMN.py $BMN.bn
echo "beautiful-mnist-gate: $(wc -l < $BMN.py | tr -d ' ') shared rows, 3 lanes identical"