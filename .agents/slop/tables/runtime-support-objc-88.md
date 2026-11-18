<!-- FROM: tinybendygrad/runtime/support/objc.bend:96 -->
# BLOCK:
# WHAT IS PORTED, DEF BY DEF.
#
#   :6-21  the ownership lattice      PORTED  Idr.{retained,own,release,finalize}
#   :11-12  __hash__/__eq__ on .value PORTED  Idr.eq
#   :13-14  __del__'s guard           PORTED  Idr.finalize
#   :23    returns_retained           PORTED  Owned.of, Msg.retain
#   :25    CDLL(find_library)         WALL 1
#   :26-27 restype + the SEL cache    PORTED  Sels  (the cache IS the type)
#   :28    objc_getClass.restype      WALL 1
#   :29    the pool pair              PORTED  the ASYMMETRY, see POOL_*
#   :30-32 dispatch_data_create       PARTIAL WALL 1, but its OWNERSHIP IS PORTED
#   :34    msg's five parameters      PORTED  Msg
#   :36    the argtypes precedence    PORTED  msg_argtypes  <- the headline rule
#   :37    the call shape             PORTED  msg_args, Tr.emit
#   :38    retain -> returns_retained PORTED  Owned.of
#   :49    objc_getClass              WALL 3
#   :53-61 __setattr__ / _inherit     PORTED  as an explicit order, see INHERIT
#   :63-67 _inherit's traversal       PORTED  inh.go
#   :69-73 _addmeth                   PORTED  Meth, mangle, subst
#   :70    the selector-name mangling PORTED  mangle
#   :71-72 the instancetype arms      PORTED  subst
#   :73    the clsmeth arm            PORTED  Meth.clsmeth
#   :75-77 class Spec                 WALL 3
#
# THE ARGUMENT MANGLING, and it is TWO steps with an ORDER between them that
# a one-step reading gets wrong. `nm = m[0].strip(':').replace(':', '_')`.
#
#   `strip(':')` removes colons from BOTH ends -- so a SELECTOR ENDING IN A
#   colon does not get a trailing underscore. `newBufferWithLength:options:`
#   mangles to `newBufferWithLength_options`, not `...options_`. Measured
#   (`mangle_3`, `mangle_trailing_colon_keeps_underscore`).
#
#   `replace(':','_')` then maps every REMAINING colon. `dispatchThreadgroups:
#
# The two steps commute on the INTERIOR but NOT on the ends, so the gate runs
# both orders: `mangle_order_swap` asserts the two spellings agree, and it
# does -- which is the theorem, not the point. The point is `mangle_3`.
# END BLOCK
