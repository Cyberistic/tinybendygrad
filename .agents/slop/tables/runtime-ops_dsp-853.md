<!-- FROM: tinybendygrad/runtime/ops_dsp.bend:853 -->
# BLOCK:
# THE ENTRY SHIM, DSPRenderer._render_entry, :27-44. Every line is a pure string
# function of the PARAM list and the index, which is what makes it gateable.
#
# THE FOUR PHASES, and the trace order below encodes them:
#
#   four FIXED lines  the header, the DCVS request, the power set, the sc>>24 test
#   one sz_or_val     PER PARAM -- ALWAYS, ALU or not -- at `pra[0].buf.pv + i*8`
#   one off + mmap    PER GLOBAL, named by the PARAM's OWN index
#   the tail          timer, the call, the munmaps, `return 0; }`
#
# THE INDEX IS THE PARAM INDEX, NOT A COMPACTED COUNTER. :35 and :37 both say
# `for i,b in enumerate(bufs)` and FILTER, so `off1`/`buf_1`/`pra[4]` name the second
# param even when the first is ALU. MEASURED on the `agga` fixture -- ALU, GLOBAL,
# GLOBAL, ALU -- where the mmap lines are `buf_1`/`pra[4]` and `buf_2`/`pra[5]` and
# the `off` subscripts are 1 and 2, NOT 0 and 1. `dsp_e_agga_*` is that row family,
# and a port that compacted the counter would move it and NOTHING else.
# END BLOCK

# THE ENTRY SHIM, DSPRenderer._render_entry, :27-44. Every line is a pure string
# function of the PARAM list and the index, which is what makes it gateable.
#
# THE FOUR PHASES, and the trace order below encodes them:
#
#   four FIXED lines  the header, the DCVS request, the power set, the sc>>24 test
#   one sz_or_val     PER PARAM -- ALWAYS, ALU or not -- at `pra[0].buf.pv + i*8`
#   one off + mmap    PER GLOBAL, named by the PARAM's OWN index
#   the tail          timer, the call, the munmaps, `return 0; }`
#
# THE INDEX IS THE PARAM INDEX, NOT A COMPACTED COUNTER. :35 and :37 both say
# `for i,b in enumerate(bufs)` and FILTER, so `off1`/`buf_1`/`pra[4]` name the second
# param even when the first is ALU. MEASURED on the `agga` fixture -- ALU, GLOBAL,
# GLOBAL, ALU -- where the mmap lines are `buf_1`/`pra[4]` and `buf_2`/`pra[5]` and
# the `off` subscripts are 1 and 2, NOT 0 and 1. `dsp_e_agga_*` is that row family,
# and a port that compacted the counter would move it and NOTHING else.
