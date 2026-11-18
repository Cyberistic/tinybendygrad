<!-- FROM: tinybendygrad/renderer/llvmir.bend:526 -->
# BLOCK:
# ONE print for the WHOLE table, so `IO.print`'s own newline is the only frame and
# the oracle's single trailing "\n" is its match.
# END BLOCK

# RULE 2, the PREDICATED LOAD (llvmir.py:86-93). EIGHT lines -- the longest
# emitter in the file -- and every one is a row.
#
#     br label %X_entry / X_entry: / br i1 %mask, label %X_load, label %X_exit
#     X_load: / %X_yes = load [volatile ]TY, TY* %idx
#     br label %X_exit / X_exit: / %X = phi TY [%X_yes, %X_load], [%alt, %X_entry]
#
# FOUR `lt` CALLS and they are not one: the `load` takes the INDEX's dtype at the
# INDEX's own count, the pointer takes that count AND `ptr`, and the `phi` takes
# `x.dtype` at `x.max_numel()`. A reader that spells one `ty` and uses it four
# times agrees with CPython whenever the index and the loaded value share a dtype
# and a width -- which is the only relationship a first fixture can have, because
# both types come from one graph.
#
# `volatile ` IS PART OF THE FRAGMENT (llvmir.py:90 spells
# `{'volatile ' if ... else ''}`), so the volatile line reads `load volatile
# float, float*` -- one space, from the fragment -- and not `load  float`.
