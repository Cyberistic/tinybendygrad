<!-- FROM: tinybendygrad/runtime/support/c.bend:302 -->
# BLOCK:
# M2 is a theorem, and it is measured rather than argued. These three defs and
# their three rows exist only to say so.
#
# `__set_name__` appends only when `hasattr(owner, "_real_fields_")`, and then
# sets `idx = len(_real_fields_) - 1`. So the two arms agree unless the owner
# LACKS the attribute while the prior length is nonzero -- and the length is
# nonzero only if something appended, which is what creates the attribute. The
# oracle WATCHED four real `__set_name__` calls and collected
# `(hasattr, len-before)` = `(False,0), (True,1), (True,2), (True,3)`: never
# `(False, n>0)`. So `Field.set_name.idx(has_real, n) == n` over the whole
# reachable domain, the mutation "return n" is the IDENTITY on values, and no
# fixture can separate them. `ops_amd`'s `floor(floor(a/b)/c)` is the same shape.
#
# The inherited case is in the list: `Sub(Three)` sees `hasattr` True with three
# entries, because `hasattr` walks the MRO and `_real_fields_` was set on `Three`.
# END BLOCK

# M2 is a theorem, and it is measured rather than argued. These three defs and
# their three rows exist only to say so.
#
# `__set_name__` appends only when `hasattr(owner, "_real_fields_")`, and then
# sets `idx = len(_real_fields_) - 1`. So the two arms agree unless the owner
# LACKS the attribute while the prior length is nonzero -- and the length is
# nonzero only if something appended, which is what creates the attribute. The
# oracle WATCHED four real `__set_name__` calls and collected
# `(hasattr, len-before)` = `(False,0), (True,1), (True,2), (True,3)`: never
# `(False, n>0)`. So `Field.set_name.idx(has_real, n) == n` over the whole
# reachable domain, the mutation "return n" is the IDENTITY on values, and no
# fixture can separate them. `ops_amd`'s `floor(floor(a/b)/c)` is the same shape.
#
# The inherited case is in the list: `Sub(Three)` sees `hasattr` True with three
# entries, because `hasattr` walks the MRO and `_real_fields_` was set on `Three`.
