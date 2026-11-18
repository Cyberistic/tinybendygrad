<!-- FROM: tinybendygrad/engine/realize.bend:2205 -->
# BLOCK:
# THE GATE'S ROWS AND WHAT EACH ROW IS FOR.
# (The prose of this block was cut in the source; the TABLE is here.)
#
# THE GATE, and what each row is FOR.
#
#   arena_n=42    the fixture is 42 nodes, so a MISSING fixture node moves this
#                 and every row that reads a later index.
#   flat_len=1    realize.py:204 is ONE rule.
#   va_len=2      realize.py:214 is `PatternMatcher([...]) + pm_flatten_linear`, so
#                 TWO entries -- and the second is the FIRST table's rule.
#   beam_len=1    realize.py:217 is ONE rule.
#   arg_len=2     realize.py:15 over `(prog, g0, g1)` is two arg uops.
#   arg_len_b=1   ... and ONE after the bound variable is dropped.
#   arg_len_var=1 realize.py:16 AT THE PIN FILTERS `is_variable`, SO AN UNBOUND
#                 variable is dropped too: the fixture's CALL 20 passes `(g0, m)`
#                 and the answer is one. the pre-PIN filter said two, and that is
#                 THE WHOLE OF THE FILTER CHANGE.
#   oi_out_p=1    realize.py:24, a PROGRAM's `arg.outs` is `(0,)`.
#   oi_out_s=1    realize.py:25, a STORE is `(0,)`.
#   oi_in_p=1     realize.py:24, a PROGRAM's `arg.ins` is `(1,)`.
#   oi_in_e=1     realize.py:26, `encdec` is `range(1, 2)` for a 2-arg call, AND THE
#                 second argument is the unbound `n` which the PIN's filter drops.
#                 THE PRE-PIN ANSWER WAS `range(1, 3)` AND `2`.
#   oi_out_v=0    realize.py:27, `validate` is NOT `encdec`, so `(), ()`.
#   oi_in_v=0     ... the second half of that pair.
#   wbuf_p=0      realize.py:33 keeps only `Ops.BUFFER`, and a PARAM is not one.
#   wbuf_buf=1    ... and a BUFFER argument IS one. Two rows, because a filter that
#                 dropped everything would move only `wbuf_p`.
#   kern_p=1      realize.py:41, one device.
#   kern_v=0      realize.py:40, a `validate` call enqueues no kernel.
#   ka_none_len=1   realize.py:17 at the PIN: a program with no variable answers one
#                   ENTRY, AND IT IS THE BUFFER's ADDRESS.
#   ka_none_addr=1  ... and it is a `GETADDR`.
#   ka_zero_len=1   A VARIABLE BOUND TO ZERO IS STILL A VARIABLE.
#   ka_zero_cast=1  ... and its value is a `CAST` over the CONST 0, NOT A MISS.
#   ka_unb_len=1    AN UNBOUND VARIABLE IS ONE ENTRY.
#   ka_unb_param=1  ... and it is a `PARAM`.
#   ka_unb_slotless=1 ... and its slot is the PIN's `-1`: the slotless var read.
#   ka_unb_arglen=0  and `get_call_arg_uops` drops it, so the call has no args.
#   ka_af_len=2      AN ARG PRECEDES A BUFFER: TWO ENTRIES.
#   ka_af_p0=1       ... AND THE ARG IS ENTRY ZERO.
#   ka_af_a1=1       ... and the BUFFER's address is entry one. the order is the
#                    slot order, not "the buffers first".
#   ka_af_slotless=1 ... AND THE ARG's SLOT IS `-1`.
#   ka_bf_len=2      THE MIRROR: A BUFFER PRECEDES AN ARG.
#   ka_bf_a0=1       ... AND THE BUFFER's ADDRESS IS ENTRY ZERO.
#   ka_bf_p1=1       ... AND THE ARG IS ENTRY ONE.
#   ka_bf_slotless=1 ... AND THE ARG's SLOT IS `-1`.
#   ka_sh_len=2      A VARIABLE THAT SHADOWS A GLOBAL's NAME.
#   ka_sh_cast=1     ... and the variable's own value is a `CAST`, not the
#                    GLOBAL's ADDRESS.
#   ka_sh_a0=1       ... and the global's address is still entry zero.
#   name_p=k1     realize.py:48 reads `ast.src[0].arg.name`, the KERNEL name and not
#                 the call's. A STRING row, because this is the one reader where a
#                 wrong `arg` would give a plausible wrong STRING.
#   res_len=2     realize.py:132, one resolved entry per arg uop.
#   res_slot0=1   THE SWAP: `inputs=(g1,g0)` answers `g1` for slot 0.
#   res_slot1=1   ... and `g0` for slot 1.
#   res_ms_same=1 the `_resolve` MSTACK WALL, printed rather than hidden: arm 0 is
#                 the VIEW arm and a BITCAST is a view, so the wall is real.
#   dnum_p=0      realize.py:139, no DEVICE axis and no `_device_num`.
#   dnum_d=1      ... a DEVICE-axis RANGE.
#   dnum_n=1      ... a `_device_num` PARAM. Two code paths, two rows.
#   gcc_p=1       realize.py:227, an uncompiled kernel still needs lowering.
#   gcc_c=0       ... a PROGRAM whose `src[-1]` is a BINARY is ALREADY compiled.
#   gcc_s=0       ... a STORE body is not a PROGRAM and not a SINK.
#   gcc_k=1       ... a SINK body with a `KernelInfo` IS.
#   est_copy_s=1  realize.py:59, a copy carries a byte count.
#   est_copy_p=0  ... and a kernel does not.
#   ctx_stats=1   realize.py:120, `update_stats` defaults True.
#   ctx_jit=0     realize.py:122, `jit` defaults False.
#   ctx_wait=0    realize.py:123, `wait` defaults False.
#   ctx_cache=1   realize.py:126, `cache` defaults True.
#   ctx_timeout=0 realize.py:125, `timeout` defaults None.
#   ctx_inputs=0  realize.py:121, `input_uops` defaults `()`.
#   ctx_time=1    realize.py:288, `time_call`'s `wait=True`.
#   ctx_time_cache=0  ... and its `cache=False`. Two rows on ONE constructor.
#   lin_fired=1   realize.py:206, a nested LINEAR IS spliced.
#   lin_len=2     ... and the result has TWO srcs where the input had two as well --
#                 the count is what says the CHILDREN moved, and `lin_first_is_call`
#                 is the row that says WHICH.
#   lin_first=1   the first src of the rewritten LINEAR is the inner CALL, i.e. the
#                 nested LINEAR was INLINED rather than kept.
#   lin_none=9    and a LINEAR with NO nested child is REJECTED by
#                 `custom_early_reject`, so `rewrite` answers `VSkip`, which
#                 `show_v` spells `9` and Python spells `None`. This is the row
#                 that makes `early_reject` load-bearing HERE, which it is not in
#                 `spec.bend`: drop the reject set and this becomes `1`.
#   beam_fired=1  realize.py:219, `sink.arg.beam == 0` so the body fires.
#   beam_new=7    ... and the rewritten sink's `KernelInfo.beam` IS the ctx value.
#   beam_skip=9   a sink that already carries a beam is left alone, so `rewrite`
#                 answers `VSkip` where `beam_fired` answers `VTrue`. This is the
#                 row that makes `sink.arg.beam == 0` load-bearing: drop that
#                 conjunct and this becomes `1`.
#   ex_copy=0     realize.py:265, a CALL over a STORE is `exec_copy`, tag 0.
#   ex_prog=1     realize.py:266, a CALL over a PROGRAM is tag 1.
#   ex_valid=2    realize.py:268, a CALL over `validate` is tag 2.
#   ex_encdec=9   realize.py:269's rule carries `arg="validate"`, so an `encdec`
#                 body is claimed by NO rule: `9` is Python's `None`.
#   ex_none=9     a LINEAR is not a CALL at all.
