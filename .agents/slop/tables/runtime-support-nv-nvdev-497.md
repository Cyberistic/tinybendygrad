<!-- FROM: tinybendygrad/runtime/support/nv/nvdev.bend:497 -->
# BLOCK:
# :58 `(self.entry(entry_id) & 1 == 1) if self.lv < level_cnt - 1 else True`.
# The `else True` is not a default: at and above the top level EVERY entry is a
# page, and getting the comparison the wrong way round makes the top level a
# directory.
# the stored WORD is injected, and it is a parameter rather than a constant.
# :58 `return (self.entry(entry_id) & 1 == 1) if self.lv < level_cnt - 1 else True`
# reads DEVICE MEMORY for the test, and at every level below the top the answer
# therefore DEPENDS ON WHAT WAS WRITTEN. `nv.stored_word` returning a literal 0
# made the port answer False at every such level regardless of the store, which is
# a claim about the device rather than a port of the predicate. The word is a
# parameter of `nv.pte_ispage` now, and the gate passes both 0 and 1 so the branch
# is exercised in BOTH directions.
# END BLOCK
