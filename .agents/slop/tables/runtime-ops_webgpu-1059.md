<!-- FROM: tinybendygrad/runtime/ops_webgpu.bend:1059 -->
# BLOCK:
# ops_webgpu.py:69-147 -- one program call, as the step list it is. Every step is
# one line range of the Python and takes the `Pass` it is handed, so the order is
# the whole of `prog.call` and nothing else.
#
# the `raise` is in the trace (see the raise): once a pop has reported an error
# no later step records anything, so these steps need no guard of their own and a
# refusal shows up as a truncated trace -- which is exactly what the four
# `wg_refuse_*` rows read.
# :71, and the dispatch geometry :123 reads. `local_size` is recorded and never
# dispatched on: ops_webgpu.py never reads it (see wgsl.bend owes, item 3).
# the parameter is `local`, not `ls`: a pattern binder of the same name shadows it
# and the Pass then keeps the 0 it was born with. measured: `wg_call_ls_recorded`
# printed 0 until this was renamed.
# END BLOCK

# ops_webgpu.py:69-147 -- one program call, as the step list it is. Every step is
# one line range of the Python and takes the `Pass` it is handed, so the order is
# the whole of `prog.call` and nothing else.
#
# the `raise` is in the trace (see the raise): once a pop has reported an error
# no later step records anything, so these steps need no guard of their own and a
# refusal shows up as a truncated trace -- which is exactly what the four
# `wg_refuse_*` rows read.
# :71, and the dispatch geometry :123 reads. `local_size` is recorded and never
# dispatched on: ops_webgpu.py never reads it (see wgsl.bend owes, item 3).
# the parameter is `local`, not `ls`: a pattern binder of the same name shadows it
# and the Pass then keeps the 0 it was born with. measured: `wg_call_ls_recorded`
# printed 0 until this was renamed.
