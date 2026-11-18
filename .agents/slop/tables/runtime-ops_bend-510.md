<!-- FROM: tinybendygrad/runtime/ops_bend.bend:510 -->
# BLOCK:
# WHAT IS NOT PORTED: `_, nuops, nbufs = head.split()` at :185 raises ValueError
# on a header that is not exactly three fields. `parse` here answers 0 for both
# counts instead, so a malformed header is a WRONG ANSWER and not a refusal. That
# is stated because it is the one place `parse` is weaker than the Python, and
# `bend_parse_short_header` is the row that records it.
# END BLOCK
