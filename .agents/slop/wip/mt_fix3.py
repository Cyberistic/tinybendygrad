import re
p = 'tinybendygrad/runtime/ops_metal.bend'
s = open(p).read()

OLD_PAT = '''def run_pat() -> List<&2, Call>:
  [Call{CALL_MSGSEND, SEL_COMMANDBUFFER(), 0},
   Call{CALL_MSGSEND, SEL_COMPUTEENCODER(), 0},
   Call{CALL_MSGSEND, SEL_WAITFENCE(), 0},
   Call{CALL_MSGSEND, SEL_USERESOURCES(), 0},
   Call{CALL_MSGSEND, SEL_SETPIPESTATE(), 0},
   Call{CALL_MSGSEND, SEL_DISPATCH(), 0},
   Call{CALL_MSGSEND, SEL_EXECUTECMDS(), 2},
   Call{CALL_MSGSEND, SEL_UPDATEFENCE(), 0},
   Call{CALL_MSGSEND, SEL_ENDENCODING(), 0},
   Call{CALL_MSGSEND, SEL_SIGNALEVENT(), 0},
   Call{CALL_MSGSEND, SEL_COMMIT(), 0}]'''

NEW_PAT = '''# THE ELEVEN msgSENDS, with EVERY argument spelled, and the four that are not
# zero are the four the source computes: the FENCE handle (:141 and :152),
# `1 + n + i` (:148), `zero` (:149) and `count` (:151). Spelling them is what
# makes the row an IDENTITY check and not an order check -- the first version of
# this pattern had zeros in all four and printed False, which is a row that says
# nothing about the order and a bad way to learn that.
#
# THE FENCE HANDLE IS NOT ZERO and that is not an accident of the fixture: it is
# minted by the DEVICE's trace during `__init__` and the QUEUE's trace is a
# different one, which is faithful -- `MetalQueue.h` starts empty in Python too.
# So the handle is a number from another arena and the row spells it rather than
# pretending the two traces share a counter.
def run_pat(d: Dev, n: U32) -> List<&2, Call>:
  [Call{CALL_MSGSEND, SEL_COMMANDBUFFER(), 0},
   Call{CALL_MSGSEND, SEL_COMPUTEENCODER(), 0},
   Call{CALL_MSGSEND, SEL_WAITFENCE(), Dev.fence(d)},
   Call{CALL_MSGSEND, SEL_USERESOURCES(), Dev.nres(d)},
   Call{CALL_MSGSEND, SEL_SETPIPESTATE(), hdr_pipe(n, 0)},
   Call{CALL_MSGSEND, SEL_DISPATCH(), fx_zero()},
   Call{CALL_MSGSEND, SEL_EXECUTECMDS(), n},
   Call{CALL_MSGSEND, SEL_UPDATEFENCE(), Dev.fence(d)},
   Call{CALL_MSGSEND, SEL_ENDENCODING(), 0},
   Call{CALL_MSGSEND, SEL_SIGNALEVENT(), 0},
   Call{CALL_MSGSEND, SEL_COMMIT(), 0}]'''

assert s.count(OLD_PAT) == 1
s = s.replace(OLD_PAT, NEW_PAT)
s = s.replace('    row("mt_run_order", seq(t, run_pat()))',
              '    row("mt_run_order", seq(t, run_pat(d, 2)))')

OLD_HAS = '    row("mt_has_absent3", Bool.not(seq(t, [Call{CALL_MSGSEND, SEL_DISPATCH(), 999}])))'
NEW_HAS = '''    row("mt_has_absent3", Bool.not(seq(t, [Call{CALL_MSGSEND, SEL_DISPATCH(), 999}])))
    # A pattern that occurs ONLY LATE in the trace. The good matcher scans the
    # WHOLE trace; mutation M16 sets the fuel to the PATTERN length, so a
    # ONE-entry pattern would only ever look at entry 0. These three rows are
    # what makes M16 move more than one row, and they are the fixture the
    # WebGPU template's M23 says a subsequence matcher needs.
    +tl : Tr <- IO.pure(Tr, q.submit(fx_dev(), q.timestamp(fx_q(0))))
    row("mt_has_late", seq(tl, [Call{CALL_MSGSEND, SEL_COMMIT(), 0}]))
    row("mt_has_late2", seq(tl, [Call{CALL_STORE, slot_at(SLOT_CBUF(), 1), 0}]))
    row("mt_has_late_absent", Bool.not(seq(tl, [Call{CALL_MSGSEND, SEL_ENDENCODING(), 1}])))'''
assert s.count(OLD_HAS) == 1
s = s.replace(OLD_HAS, NEW_HAS)

OLD_ICB = '    lrow("mt_icb_store", kinds(CALL_STORE(), bt))'
NEW_ICB = '''    lrow("mt_icb_store", kinds(CALL_STORE(), bt))
    lrow("mt_icb_storeslots", store_slots(bt))
    # the per-command ORDER, :259 then :261-265. THE COUNTS (`mt_icb_cmds`,
    # `mt_icb_retain`) CANNOT see a swap of the two, which is what mutation M38
    # measured: 0 rows, and this row is the answer to that.
    row("mt_icb_cmd_order", seq(bt, [Call{CALL_ICBCMD, sel_ix("indirectComputeCommandAtIndex"), 0},
      Call{CALL_RETAIN, sel_ix("retain"), 0},
      Call{CALL_NEWPIPE, sel_ix("newComputePipelineStateWithDescriptor_options_reflection_error"), 0},
      Call{CALL_SETKBUF, sel_ix("setKernelBuffer_offset_atIndex"), 0},
      Call{CALL_CONCDISP, sel_ix("concurrentDispatchThreadgroups_threadsPerThreadgroup"), 0},
      Call{CALL_SETBAR, sel_ix("setBarrier"), 0},
      Call{CALL_ICBCMD, sel_ix("indirectComputeCommandAtIndex"), 1},
      Call{CALL_RETAIN, sel_ix("retain"), 1}]))'''
assert s.count(OLD_ICB) == 1
s = s.replace(OLD_ICB, NEW_ICB)
open(p, 'w').write(s)
print("ok")
