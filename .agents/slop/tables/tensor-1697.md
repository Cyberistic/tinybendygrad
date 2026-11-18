<!-- FROM: tinybendygrad/tensor.bend:1697 -->
# BLOCK:
# `linear_with_vars` (tensor.py:167-210), 44 lines, the calls in order:
#
#   :167 `@rewrite_group(...)`                              P3, WALL 3
#   :171 `graph_rewrite(sink, PatternMatcher([]))`         P3, WALL 3
#   :173 `u.dtype in dtypes.weaks and u.device is not None` PORTED (fold)
#   :176 `{x.base for x in sink.src}`                        PORTED (fold)
#   :178 `x.op in {STAGE, DETACH, CONTIGUOUS_BACKWARD}`      PORTED (op_in)
#   :179 `x.storage_base`                                   P3, ops.py:801
#   :184 `x.replace(src=...)`                                P3, ops.py:310
#   :185 `UOp.new_buffer`                                    WALL 2
#   :186 `u.needs_storage()`                                 P3, ops.py:780
#   :192 `src.is_virtual or src.on_disk() or src.has_buffer_identity()`   P3
#   :194 `contiguous_mops_to_view(None, u, src)`             SCHEDULE
#   :196 `UOp.new_buffer(...).reshape(...).shrink_to(...)`   WALL 2
#   :197 `src.axis`                                          P3, ops.py:718
#   :198 `buf.unshard(src.axis)`                             P3, ops.py:692
#   :204 `graph_rewrite(u.src[0], pm_drop_after)`            P3, WALL 3
#   :207 `UOp.sink(...).substitute(becomes_map, walk=True)`  P3, WALL 3
#   :210 `create_linear_with_vars(sink)`                     SCHEDULE
#
