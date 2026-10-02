p = 'tinybendygrad/runtime/ops_metal.bend'
s = open(p).read()

# 1. :259 builds ALL the command handles, THEN :260 loops over them. The two
#    loops are SEPARATE and the first version of the pattern interleaved them.
OLD = '''    row("mt_icb_cmd_order", seq(bt, [Call{CALL_ICBCMD, sel_ix("indirectComputeCommandAtIndex"), 0},
      Call{CALL_RETAIN, sel_ix("retain"), 0},
      Call{CALL_NEWPIPE, sel_ix("newComputePipelineStateWithDescriptor_options_reflection_error"), 0},
      Call{CALL_SETKBUF, sel_ix("setKernelBuffer_offset_atIndex"), 0},
      Call{CALL_CONCDISP, sel_ix("concurrentDispatchThreadgroups_threadsPerThreadgroup"), 0},
      Call{CALL_SETBAR, sel_ix("setBarrier"), 0},
      Call{CALL_ICBCMD, sel_ix("indirectComputeCommandAtIndex"), 1},
      Call{CALL_RETAIN, sel_ix("retain"), 1}]))'''
NEW = '''    # :259's list comprehension and :260's `zip` are TWO SEPARATE LOOPS: every
    # command handle is taken FIRST and only then is each one set up. The first
    # version of this pattern interleaved them and printed False, which is a row
    # that was wrong about the source and right about nothing.
    row("mt_icb_cmd_order", seq(bt, [Call{CALL_ICBCMD, sel_ix("indirectComputeCommandAtIndex"), 0},
      Call{CALL_RETAIN, sel_ix("retain"), 0},
      Call{CALL_ICBCMD, sel_ix("indirectComputeCommandAtIndex"), 1},
      Call{CALL_RETAIN, sel_ix("retain"), 1},
      Call{CALL_NEWPIPE, sel_ix("newComputePipelineStateWithDescriptor_options_reflection_error"), 0},
      Call{CALL_SETKBUF, sel_ix("setKernelBuffer_offset_atIndex"), 0},
      Call{CALL_CONCDISP, sel_ix("concurrentDispatchThreadgroups_threadsPerThreadgroup"), 0},
      Call{CALL_SETBAR, sel_ix("setBarrier"), 0},
      Call{CALL_NEWPIPE, sel_ix("newComputePipelineStateWithDescriptor_options_reflection_error"), 0},
      Call{CALL_SETKBUF, sel_ix("setKernelBuffer_offset_atIndex"), 256}]))'''
assert s.count(OLD) == 1
s = s.replace(OLD, NEW)

# 2. the local-size refusal STOPS the command before it binds a buffer, so the
#    row must assert the ABSENCE of the bind, not its presence.
OLD2 = '''    row("mt_icb_local_order", seq(c1, [Call{CALL_SETCOMPFUNC, sel_ix("setComputeFunction"), 0},
      Call{CALL_SETKBUF, sel_ix("setKernelBuffer_offset_atIndex"), 0}]))'''
NEW2 = '''    # :262 sits BETWEEN the pipeline and the bind, so a command whose local size
    # is too big is left with a pipeline and NO BUFFER. `mt_icb_local_bound` is
    # the negative row and it is the one that says the refusal is in the right
    # PLACE; the positive half only says the pipeline was built.
    row("mt_icb_local_pipeline", seq(c1, [Call{CALL_SETCOMPFUNC, sel_ix("setComputeFunction"), 0},
      Call{CALL_NEWPIPE, sel_ix("newComputePipelineStateWithDescriptor_options_reflection_error"), 0}]))
    row("mt_icb_local_bound", Bool.not(seq(c1, [Call{CALL_SETKBUF, sel_ix("setKernelBuffer_offset_atIndex"), 0}])))'''
assert s.count(OLD2) == 1
s = s.replace(OLD2, NEW2)

# 3. the late pattern must name a (sel, arg) pair that really occurs
OLD3 = '    row("mt_has_late2", seq(tl, [Call{CALL_STORE, slot_at(SLOT_CBUF(), 1), 0}]))'
NEW3 = '    row("mt_has_late2", seq(tl, [Call{CALL_STORE, slot_at(SLOT_PENDING(), 1), 0}]))'
assert s.count(OLD3) == 1
s = s.replace(OLD3, NEW3)
open(p, 'w').write(s)
print("ok")
