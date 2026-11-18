<!-- FROM: tinybendygrad/runtime/support/am/ip.bend:29 -->
# BLOCK:
# WHAT IS NOT PORTED -- the six walls, each with its own `TODO(p3)` markers
# in the WALLS section below, and each naming the lines it covers:
#   WALL 1  register ACCESS and `AMDReg.encode`'s bit POSITIONS           :367 :411
#   WALL 2  `hasattr` / `getattr` NAME probing
#     ..................................................................... :17 :21 :22 :25 :56 :58 :103 :260 :359 :389 :477 :506 :646
#   WALL 3  `functools.cache` memoisation                                :177 :230
#   WALL 4  firmware BLOBS, `from_buffer`, `int(round(watts))`           :228 :250
#   WALL 5  thirteen `wait_cond` polls and six `time.sleep`s             :113 :117 :121 :219 :222 :271 :284 :346 :393 :417 :450 :584 :640 :656 :692 :695 :702 :704 :717
#   WALL 6  the memory manager: `mm.palloc`, `mm.map_range`, `paddrs`    :278 :331
# END BLOCK
