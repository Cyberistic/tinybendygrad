<!-- FROM: tinybendygrad/runtime/ops_python.bend:30 -->
# BLOCK:
# THE DISPATCH, IN ops_python.py's ORDER, EACH ARM WITH ITS LINE.
#
#   ops_python.py:15-31   _load/_store/_step        PORTED (the v1 lanes)
#   ops_python.py:33-44   wmma                      WALL  (tensor cores)
#   ops_python.py:52-157  PythonProgram.__call__    arm by arm, below
#
#   :67  BACKEDGE       PORTED  the loop head
#   :70  END            PORTED
#   :73  IF             PORTED  exec_masks, one Bool per work item at warp 1
#   :77  ENDIF          PORTED
#   :81  barrier/sink/noop/group/custom_function, RANGE(void)  ported (no-ops)
#   :85  STORE          PORTED  gated, vector, stepped
#   :93  AFTER, BITCAST@GLOBAL/LOCAL    PORTED (pass-through)
#   tinygrad/runtime/ops_python.py:97 PARAM@ALU      PORTED  reads a `vals` entry -- upstream's `pargs.pop(0)` symbol=__call__
#   :95  PARAM, BUFFER  PORTED  binds a buffer, or allocates zeros
#   :106 BINARY         WALL  ops_python.py:106 -- `memoryview(u.arg)` is raw
#                              bytes carried inside the UOp, with no wire spelling
#   :107 SPECIAL        PORTED  'g' from the grid; 'l' is 0 at warp 1
#   :110 CONST          PORTED
#   :111 INDEX, SHRINK  PORTED for the ALU and buffer arms; WALL for the
#                              is_image_shape arm, which needs `_shape`
#   :123 RANGE          PORTED  the counter lives in its own arena slot
#   :132 STACK          PORTED
#   :133 BITCAST        PORTED  v1 lanes only (Python asserts equal itemsize)
#   :134 CAST           PORTED  v1 lanes only, see THE WIDE DTYPES
#   :136 LOAD           PORTED  scalar, vector, and the gated arm
#   :143 CALL           WALL  ops_python.py:143 -- a ctypes FFI call into a
#                              loaded shared object; not a uop the emulator
#                              can answer without the library
#   :150 WMMA           WALL  ops_python.py:150, as briefed
#   :151 GroupOp.ALU    PORTED, by REUSING symbolic.bend's two lanes
#
