<!-- FROM: tinybendygrad/runtime/ops_python.bend:700 -->
# BLOCK:
# THE PROGRAM TABLE. `self.uops` and `values` from ops_python, kept apart
# because they behave differently. The uop list is READ-ONLY for a whole launch
# -- a `List<&2, Uop>` is Data, so every lookup is free and copies nothing --
# while the values arena is a REBOUND list: `List.set` copies only the path it
# rebuilds, which is what keeps an assignment affordable.
#
# the stride is fixed at parse time, which is what the shape of the machine's second
# requirement was about. ops_python's `values` is keyed by UOp, so a RANGE body
# overwrites exactly the entries the first pass wrote and a bump allocator would
# let the second pass read its own history. So uop i owns the FIXED slot run
# `slot_i .. slot_i + run_i - 1`, assigned in uop order, and a re-executed uop
# lands back on its own slots.
#
# MEASURED over the 25 gate packets (1310 uops; .agents/slop/x-shape.py): every
# run is 1 except LOAD (its `k:vec:` count) and STACK (its src count, max 4). A
# vector LOAD's value in Python is `[[v]]*load_sz` -- a run of warp-runs -- and
# at warp 1 (see LOCAL SIZE) every inner run is length 1, so the FLAT run is
# `load_sz` and each consumer below reads it flat. The one shape that breaks
# that flattening is a LOAD whose pointer src is itself a run of several (a
# gather): measured none in 117 LOADs, longest pointer run 1. That is WALL 5.
# `<arg>` decoded into a KIND and two numbers. The letters of A1 become kinds
# rather than a field, so the walk reads one number: 2/3 are a PARAM of addrspace
# g/l (which binds the next packet buffer), 4 is addrspace r and 5 is a BUFFER
# (both `bytearray` scratch), 6 is addrspace a (a `vals` entry), 8 is an
# INDEX/SHRINK scale and 9 a LOAD/STORE lane count -- the last two land in `run`
# at parse time and are never read again. 14 and 15 are the two refusals: a
# dtype or an op name this file does not port.
# END BLOCK

# THE PROGRAM TABLE. `self.uops` and `values` from ops_python, kept apart
# because they behave differently. The uop list is READ-ONLY for a whole launch
# -- a `List<&2, Uop>` is Data, so every lookup is free and copies nothing --
# while the values arena is a REBOUND list: `List.set` copies only the path it
# rebuilds, which is what keeps an assignment affordable.
#
# the stride is fixed at parse time, which is what the shape of the machine's second
# requirement was about. ops_python's `values` is keyed by UOp, so a RANGE body
# overwrites exactly the entries the first pass wrote and a bump allocator would
# let the second pass read its own history. So uop i owns the FIXED slot run
# `slot_i .. slot_i + run_i - 1`, assigned in uop order, and a re-executed uop
# lands back on its own slots.
#
# MEASURED over the 25 gate packets (1310 uops; .agents/slop/x-shape.py): every
# run is 1 except LOAD (its `k:vec:` count) and STACK (its src count, max 4). A
# vector LOAD's value in Python is `[[v]]*load_sz` -- a run of warp-runs -- and
# at warp 1 (see LOCAL SIZE) every inner run is length 1, so the FLAT run is
# `load_sz` and each consumer below reads it flat. The one shape that breaks
# that flattening is a LOAD whose pointer src is itself a run of several (a
# gather): measured none in 117 LOADs, longest pointer run 1. That is WALL 5.
# `<arg>` decoded into a KIND and two numbers. The letters of A1 become kinds
# rather than a field, so the walk reads one number: 2/3 are a PARAM of addrspace
# g/l (which binds the next packet buffer), 4 is addrspace r and 5 is a BUFFER
# (both `bytearray` scratch), 6 is addrspace a (a `vals` entry), 8 is an
# INDEX/SHRINK scale and 9 a LOAD/STORE lane count -- the last two land in `run`
# at parse time and are never read again. 14 and 15 are the two refusals: a
# dtype or an op name this file does not port.
