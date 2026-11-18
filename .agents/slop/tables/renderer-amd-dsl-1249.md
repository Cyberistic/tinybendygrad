<!-- FROM: tinybendygrad/renderer/amd/dsl.bend:1249 -->

# `op_bits` / `op_regs` -- :348-381. FIVE ADJUSTMENTS over the XML widths, and
# each is a CONDITIONAL on the op NAME or on the raw word, so each needs its own
# pair of rows: one that fires and one that sits next to it and does not.
#
#   cndmask  / _co_ci_  -> src2 = 32          (:356-357)  RDNA (WAVE32) only
#   VOP3SD              -> sdst = 32          (:359)      by CLASS NAME
#   cmp                 -> vdst = 32          (:360)      RDNA only
#   addr                -> 64 or 32 by saddr  (:363-365)  GLOBAL/FLAT, not SCRATCH
#   vaddr               -> max(1,offen+idxen)*32 (:367-368)
#   f8f6f4              -> src0/src1 by cbsz/blgp (:371-376)
#
# EVERY adjustment is inside `if not self._is_cdna():` EXCEPT the saddr and
# vaddr ones -- so a CDNA instruction gets cndmask/cmp/f8f6f4 differently, and
# the gate has a row for that.
