<!-- FROM: tinybendygrad/runtime/ops_python.bend:2972 -->
# BLOCK:
# THE CPYTHON-OBJECT-GRAPH PROBLEM AND THE PORT'S SPELLING.
#
#   CPython                    this port
#   ------------------------   --------------------------------------------
#   list[UOp]                  List<&2, Uop>, one `Uop` record per uop
#   UOp.op   (Ops enum)        Uop.op -> O.Op, ops.bend's tagged union
#   UOp.dtype (DType)          Uop.dt -> S.Dt, spec.bend's dtype
#   UOp.arg  (Any)             Uop.a / Uop.b, the arg SPELLED BY THE WIRE
#   UOp.src  (list[UOp])       Uop.srcs -> List<&2, U32>, arena indices
#   pickle.dumps -> bytes      the v1 TEXT PACKET
#   base64(...) -> str         NOT re-applied: the packet is already text
#
