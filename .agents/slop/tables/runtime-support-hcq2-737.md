<!-- FROM: tinybendygrad/runtime/support/hcq2.bend:737 -->
# BLOCK:
# WHAT SURVIVES THE ARENA WALK: a batch is a list of (call, devices, queue)
# triples and a call touches TWO buffers -- `get_call_outs_ins(call)[0]` is
# `(0,)` in every fixture, so ranges[0] is WRITTEN and ranges[1] is READ. That is
# the whole of `DepsTracker.access_resources` (:182-207) for these shapes.
# END BLOCK
