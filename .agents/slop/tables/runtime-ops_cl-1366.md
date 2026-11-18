<!-- FROM: tinybendygrad/runtime/ops_cl.bend:1366 -->
# BLOCK:
# cl:55-76 -- ONE PROGRAM CALL, as the step list it is. Every step is one line
# range of the Python and takes the `Prog` it is handed, so the order IS the
# whole of `__call__`: the arg loop (:57-65), then the geometry (:66, no call),
# then the launch (:68), then the `if wait:` block (:70-75).
#
# THE `raise` IS IN THE TRACE (see THE RAISE): `check` after every call, so once
# a refusal lands nothing further records and a refusal shows up as a TRUNCATED
# trace. `cl_refuse_*` reads that.
# `Arg.kind`: 0 is a `cl_mem`, 1 is a `clCreateImage` result, 2 is the boxed
# `c_int{bitsize}` scalar. The three are not decoration -- they select three
# DIFFERENT `clSetKernelArg` argument types and the image one adds a
# `clCreateImage` BEFORE the set.
# END BLOCK

# cl:55-76 -- ONE PROGRAM CALL, as the step list it is. Every step is one line
# range of the Python and takes the `Prog` it is handed, so the order IS the
# whole of `__call__`: the arg loop (:57-65), then the geometry (:66, no call),
# then the launch (:68), then the `if wait:` block (:70-75).
#
# THE `raise` IS IN THE TRACE (see THE RAISE): `check` after every call, so once
# a refusal lands nothing further records and a refusal shows up as a TRUNCATED
# trace. `cl_refuse_*` reads that.
# `Arg.kind`: 0 is a `cl_mem`, 1 is a `clCreateImage` result, 2 is the boxed
# `c_int{bitsize}` scalar. The three are not decoration -- they select three
# DIFFERENT `clSetKernelArg` argument types and the image one adds a
# `clCreateImage` BEFORE the set.
