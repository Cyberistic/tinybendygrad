<!-- FROM: tinybendygrad/renderer/wgsl.bend:1518 -->

# THE GATE. Every row is a STRING and every row carries CPython's value, so the
# two lanes print the SAME LINE and the diff of the two lanes is empty iff every
# claim holds. The rows are built as one string by a fold rather than printed
# one IO at a time: an `IO.bind` chain nine deep is a paren-counting exercise
# with no payoff, and a fold over rows is also what makes the row ORDER a
# property of this file that the Python side can copy.
#
# `r` is render.bend's `py_row` with the IO dropped: a row is a value here, not
# an effect, so a group of them is a `String` and the whole gate is one print.
# `global_max` and `local_max` are three ints each and Python's `repr` of the
# tuple is the gate's whole content, so the row needs them as decimal text. THE
# CONSTRUCTOR MATTERS: this list is WALKED by `case h <> t` on the way to
# `String.join`, and `String.join` is head-first, so `<>` (a prepend) is the
# constructor that keeps the order and `List.append(acc, [x])` would reverse it.
# -- type_map -----------------------------------------------------------------
