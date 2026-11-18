<!-- FROM: tinybendygrad/engine/realize.bend:22 -->
# BLOCK:
# THE TWO GROUPS, INVENTORIED: `[a]` is ported, `[b]` is the foreign-effect seam.
# (The prose of this block was cut in the source; the INVENTORY is here.)
#
# THE TWO GROUPS, INVENTORIED. `[a]` is ported, `[b]` is the foreign-effect seam.
#
# [a] realize.py:16   get_call_arg_uops     -- `call.src[1:]`, minus VARIABLES
# [a] realize.py:17   get_call_kernel_args  -- one entry per kernel PARAM, in slot order
# [a] realize.py:21   get_call_outs_ins     -- (outs, ins) per body op
# [a] realize.py:29   get_call_written_bufs -- outs \ ins, BUFFERs only, deduped
# [a] realize.py:35   get_call_kernels      -- the device list (non-HCQ half)
# [a] realize.py:43   get_call_name         -- the PROGRAM arm
# [a] realize.py:55   estimate_uop          -- the DISPATCH and the byte count
# [a] realize.py:118  ExecContext           -- the dataclass, field for field
# [a] realize.py:128  _resolve              -- PARAM slot lookup, view recursion
# [a] realize.py:126 symbol=_resolve  resolve_params        -- `_resolve` over `get_call_arg_uops`
# [a] realize.py:138  unwrap_multi's `has_dnum` -- the DEVICE-axis toposort fold
# [a] realize.py:204  pm_flatten_linear     -- a RULE
# [a] realize.py:209  pm_validate / _validate -- the rule TABLE and the claim
# [a] realize.py:217  pm_beam               -- a RULE, body fully ported
# [a] realize.py:227  _get_call_to_compile  -- the predicate
# [a] realize.py:237  lower_and_compile's collection -- `toposort` + filter
# [a] realize.py:264  pm_exec               -- the rule TABLE and the dispatch
# [a] realize.py:271  compile_linear        -- the STAGE ORDER
#
# [b] realize.py:57   the HCQInfo arms      -- `call.arg.aux` is DROPPED from
#                                             `CallInfo` in ops.bend
# [b] realize.py:58   Estimates             -- the FIELD is PORTED (2026-10-30)
#                                             and always `None`: `do_estimates`
#                                             is a WALL in codegen/kernel.bend
# [b] realize.py:60   first_run_cache       -- a process-global `set[bytes]`
# [b] realize.py:64   track_stats           -- GlobalCounters, DEBUG, PROFILE,
#                                             cpu_events, print, synchronize
# [b] realize.py:107  runtime_cache         -- a process-global dict
# [b] realize.py:108  get_runtime           -- `Device[d].runtime(ast.to_elf())`
# [b] realize.py:116  capturing             -- a process-global list of classes
# [b] realize.py:133  unwrap_multi's bufs   -- `UOp.buffer` needs a REALIZED buffer
# [b] realize.py:141  unwrap_multi's lanes  -- `MultiBuffer`, device.py
# [b] realize.py:148  exec_copy             -- allocators, `_transfer`, `host[:]`
# [b] realize.py:163  exec_kernel           -- the runtime call, `launch_dims`
# [b] realize.py:172  exec_validate         -- a CPU runtime + numpy
# [b] realize.py:183  exec_hcq              -- HCQInfo, timelines, ProfileGraphEntry
# [b] realize.py:225  _compile_kernel       -- `Context(x[2])`, `to_program`
# [b] realize.py:240  to_program_key / to_program_cache -- codegen, P5
# [b] realize.py:245  the worker pool and tqdm -- a subprocess pool and a bar
# [b] realize.py:275  `linear.substitute`   -- ops.py:514 symbol=substitute
# [b] realize.py:108  hcq_compile           -- `runtime/support/hcq2.py`, not ported
# [b] realize.py:279  hcq_link              -- same
# [b] realize.py:285  run_linear            -- perf_counter_us, the dispatch loop
# [b] realize.py:287  time_call             -- invalidate_caches, Tensor.ones
