<!-- FROM: tinybendygrad/runtime/support/autogen.bend:98 -->
# BLOCK:
# WHAT IS PORTED, DEF BY DEF.
#
#   :77   attrs                 PORTED   kind in [400,500), both bounds
#   :82   base_rules            PORTED as TABLE  (WALL 2 for the matcher)
#   :87   uints/ints/fps/specs  PORTED   both directions
#   :91   tmap                  PORTED   both directions
#   :98   arc_families          PORTED
#   :100  normalize             PORTED   over Python's 35 keywords
#   :107  typehint              PORTED   both directions, incl. the falsy arm
#   :112  tname, its TEMPLATES  PORTED   emit_record_pass/head/field/cell,
#                                           emit_enum_cell/dict, emit_typealias,
#                                           emit_dll_bind, emit_def_line,
#                                           emit_returns_retained, emit_in_dll,
#                                           emit_macro/_fn, emit_cfunctype,
#                                           emit_pointer, emit_array
#   tinygrad/runtime/support/autogen.py:107 `typehint`      PORTED   `Gt{nm, tnm, defd, ln}` and its readers symbol=typehint
#   :273  the main prologue     PORTED   prolog_head, prolog_objc, emit_dll_line
#   :112  tname, its DISPATCH   WALL 4   the ten-arm `match t.kind` and its
#                                           record arm -- see WALL 4 above
#   :5-80 the libclang FFI      WALL 1   46 functions MEASURED, 0 bound
#   tinygrad/runtime/support/autogen.py:30 `all_fields`      WALL 4   it is a loop over `fields(t)` calling
#                                           into tname, so it inherits WALL 4
#   :73   readext               WALL 1   file IO at a source offset
#   :194  parse_objc_spec       WALL 4   same two-descents shape, over methods
#   :209  proto                 WALL 4   same
#   :279  the exec/prune loop   WALL 3   needs CPython line numbers
# END BLOCK
