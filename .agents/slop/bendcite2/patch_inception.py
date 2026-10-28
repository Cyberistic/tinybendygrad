#!/usr/bin/env python3
"""THE `inception.bend` PATCH: every `.bend` citation inside a `D.refuse` payload
gets the tree's durable `symbol=` form, so the pointer NAMES the construct it is about.

The `D.refuse(...)` strings are DIAGNOSTIC PAYLOADS -- no computation reads them --
so editing one is a comment edit in effect, but they are CODE LINES and the
comment-only proof must list this file separately.

  .venv/bin/python .agents/slop/bendcite2/patch_inception.py <root>
"""
import sys
from pathlib import Path

REL = "tinybendygrad/extra/models/inception.bend"

# (UNIQUE OLD TEXT, NEW TEXT)
EDITS: list[tuple[str, str]] = [
  # 117
  ("the OP nn_conv2d (nn/layers.bend:937) EXISTS",
   "the OP nn_conv2d (nn/layers.bend:937 symbol=nn_conv2d) EXISTS"),
  # 121
  ("the running-statistics half is REFUSED at nn/pool.bend:415",
   "the running-statistics half is REFUSED at nn/pool.bend:416 symbol=pool_bn_running_stats"),
  # 137
  ("pool_avgpool (nn/pool.bend:261) is the UNPADDED arm only, and pool_avgpool_padded (nn/pool.bend:263) names the blocker",
   "pool_avgpool (nn/pool.bend:261 symbol=pool_avgpool) is the UNPADDED arm only, and pool_avgpool_padded (nn/pool.bend:263 symbol=pool_avgpool_padded) names the blocker"),
  # 144
  ("the padded avg_pool2d at :38 (nn/pool.bend:263)",
   "the padded avg_pool2d at :38 (nn/pool.bend:263 symbol=pool_avgpool_padded)"),
  # 157
  ("pool_maxpool (nn/pool.bend:251) is the UNPADDED arm only; pool_maxpool_padded (nn/pool.bend:253) names the blocker, and pool.bend:248-249 says why",
   "pool_maxpool (nn/pool.bend:251 symbol=pool_maxpool) is the UNPADDED arm only; pool_maxpool_padded (nn/pool.bend:253 symbol=pool_maxpool_padded) names the blocker, and pool.bend:248-249 symbol=pool_maxpool says why"),
  # 170
  ("nn_conv2d (nn/layers.bend:937) derives ni",
   "nn_conv2d (nn/layers.bend:937 symbol=nn_conv2d) derives ni"),
  # 178
  ("InceptionD.__call__ -- REFUSED PADDED MAX POOL (nn/pool.bend:253)",
   "InceptionD.__call__ -- REFUSED PADDED MAX POOL (nn/pool.bend:253 symbol=pool_maxpool_padded)"),
  # 199
  ("InceptionAux.__call__ -- REFUSED PADDED AVG POOL (nn/pool.bend:263); the kernel is 5",
   "InceptionAux.__call__ -- REFUSED PADDED AVG POOL (nn/pool.bend:263 symbol=pool_avgpool_padded); the kernel is 5"),
  # 203 -- TWO citations, one line
  ("pool_flatten (nn/pool.bend:327) EXISTS",
   "pool_flatten (nn/pool.bend:327 symbol=pool_flatten) EXISTS"),
  ("which is the -1 INFERENCE nn/pool.bend:323-325 says",
   "which is the -1 INFERENCE nn/pool.bend:323-325 symbol=pool_flatten says"),
  # 226
  ("Inception3.maxpool1 -- REFUSED PADDED MAX POOL (nn/pool.bend:253)",
   "Inception3.maxpool1 -- REFUSED PADDED MAX POOL (nn/pool.bend:253 symbol=pool_maxpool_padded)"),
  # 230
  ("Inception3.avgpool -- REFUSED PADDED AVG POOL (nn/pool.bend:263)",
   "Inception3.avgpool -- REFUSED PADDED AVG POOL (nn/pool.bend:263 symbol=pool_avgpool_padded)"),
  # 234
  ("nn_linear (nn/layers.bend:530) EXISTS",
   "nn_linear (nn/layers.bend:530 symbol=nn_linear) EXISTS"),
  # 238
  ("the padded max_pool2d at :147 via :170 (nn/pool.bend:253)",
   "the padded max_pool2d at :147 via :170 (nn/pool.bend:253 symbol=pool_maxpool_padded)"),
  # 247
  ("that IS the arm pool_avgpool_padded (nn/pool.bend:263) refuses",
   "that IS the arm pool_avgpool_padded (nn/pool.bend:263 symbol=pool_avgpool_padded) refuses"),
  # 251
  ("FidInceptionC.__call__ -- MISSING count_include_pad=False (nn/pool.bend:263)",
   "FidInceptionC.__call__ -- MISSING count_include_pad=False (nn/pool.bend:263 symbol=pool_avgpool_padded)"),
  # 255
  ("FidInceptionE1.__call__ -- MISSING count_include_pad=False (nn/pool.bend:263)",
   "FidInceptionE1.__call__ -- MISSING count_include_pad=False (nn/pool.bend:263 symbol=pool_avgpool_padded)"),
  # 259
  ("FidInceptionE2.__call__ -- REFUSED PADDED MAX POOL (nn/pool.bend:253)",
   "FidInceptionE2.__call__ -- REFUSED PADDED MAX POOL (nn/pool.bend:253 symbol=pool_maxpool_padded)"),
  # 277
  ("the same seam resnet.bend:97-98 records as 0 hits",
   "the same seam extra/models/resnet.bend:116-117 symbol=fetch records as 0 hits"),
  # 281
  ("nn/state.bend:318 get_state_dict reads state",
   "nn/state.bend:318 symbol=get_state_dict reads state"),
  # 289
  ("mo_mean (mixin/op.bend:953) IS built",
   "mo_mean (mixin/op.bend:953 symbol=mo_mean) IS built"),
  # 301
  ("which is the port's standing spelling for that (nn/layers.bend:363-367)",
   "which is the port's standing spelling for that (nn/layers.bend:363-367 symbol=nn_dot.wshape)"),
  # 305
  ("mo_sum (mixin/op.bend:853) IS built",
   "mo_sum (mixin/op.bend:854 symbol=mo_sum) IS built"),
  # 318
  ('srow("inception_first_blocker", "nn.Conv2d CLASS -- the op nn_conv2d EXISTS at nn/layers.bend:937")',
   'srow("inception_first_blocker", "nn.Conv2d CLASS -- the op nn_conv2d EXISTS at nn/layers.bend:937 symbol=nn_conv2d")'),
  # 319 -- TWO citations, one line
  ('srow("inception_pool_wall", "all 10 pool calls need a padded arm; nn/pool.bend:253 and :263 both refuse on identity_element (uop/ops.py:61)")',
   'srow("inception_pool_wall", "all 10 pool calls need a padded arm; nn/pool.bend:253 symbol=pool_maxpool_padded and nn/pool.bend:263 symbol=pool_avgpool_padded both refuse on identity_element (uop/ops.py:61)")'),
]


def main() -> int:
  root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
  p = root / REL
  s = p.read_text(encoding="utf-8")
  bad = 0
  for old, new in EDITS:
    n = s.count(old)
    if n != 1:
      print(f"SKIP (count={n}) {old[:80]!r}")
      bad += 1
      continue
    s = s.replace(old, new)
  p.write_text(s, encoding="utf-8")
  print(f"APPLIED {len(EDITS) - bad} of {len(EDITS)}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
