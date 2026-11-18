<!-- FROM: tinybendygrad/renderer/wgsl.bend:136 -->
# BLOCK:
# :34  is_nan -- `(a.bitcast(uint{bs}) & ((1 << (bs - 1)) - 1)) >
# (((1 << exp) - 1) << mant)`. The bitcast and the compare are the wall; the
# FIVE INTEGERS are not, and they are the whole rule: the mask is the sign bit
# cleared and the threshold is the largest finite magnitude.
#
# WHY THE RULE EXISTS AT ALL, AND IT IS TWO DIFFERENT RULES WITH THE SAME
# END BLOCK

# :10  packed_field -- `elems, width = 4//dt.itemsize, 8*dt.itemsize` and the
# caller's `(1 << width)-1`. Three ints, all three in the output.
#
# "a packed field of dt: the word it lives in, its offset in that word, and
# its mask. width is 8*itemsize, bool is one bit in a byte" -- wgsl.py:9,
# upstream's comment ON IT. THE THREE RETURNS ARE THREE DIFFERENT THINGS AND
# THE MASK IS THE ONE THAT IS EASY TO GET WRONG:
#   * THE **WORD** -- WHICH 32-BIT SLOT THE FIELD IS IN. `elems = 4 //
#     itemsize` IS HOW MANY OF THESE FIELDS FIT IN A WORD: FOUR `u8`, TWO
#     `u16`, ONE `u32`. SO THE WORD INDEX IS `bidx // elems` AND THE
#     ELEMENT INDEX IS `bidx % elems`.
#   * THE **OFFSET** -- THE FIELD'S BIT POSITION IN THAT WORD, AND IT IS
#     `((bidx % elems) * width)`, IN **BITS**, NOT IN ELEMENTS. SO A `u8`
#     AT ELEMENT 3 IS AT BIT 24 AND NOT AT BIT 3. THE PORT'S `shift_am` IS
#     THAT PRODUCT.
#   * THE **MASK** -- `(1 << width) - 1`, THE FIELD'S OWN BITS. AND THE
#     LAST CLAUSE OF UPSTREAM'S COMMENT IS THE GOTCHA: "bool is one bit in
#     a byte". A `bool` IS **ONE BIT** AND NOT EIGHT, SO `width = 8 *
#     itemsize` IS **WRONG** FOR A `bool` -- WHICH IS WHY `packed_field` IS
#     NEVER CALLED WITH ONE: `is_packed` EXCLUDES `dtypes.half` (itemsize
#     2) BUT **NOT** `dtypes.bool` (itemsize 1), SO A `bool` BUFFER *IS*
#     PACKED, AND THE `bool` CASE IS HANDLED SOMEWHERE ELSE.
#
# WHERE IT IS HANDLED IS UPSTREAM'S `string_rewrite` (wgsl.py:77-84), WHICH
# HAS FIVE **BARE** BITCAST RULES -- ONE FOR `half`, ONE FOR `uchar`, ONE
# FOR `char`, ONE FOR `ushort` AND ONE FOR `short` -- AND EVERY ONE OF THEM
# SPELLS THE **MASK** OUT IN THE TEXT: `&0xFF`, `<<24)>>24`, `&0xFFFF`,
# `<<16)>>16`. SO A `bool` BUFFER'S ELEMENT IS READ AS A `u32` WORD AND
# THEN NARROWED BY HAND, NOT BY `packed_field`'s MASK.
#
# AND THE `elems` DIVISION IS WHAT MAKES THE WHOLE THING WORK: WGSL HAS NO
# SUB-WORD LOADS, SO A `u8` BUFFER IS NOT A `u8` ARRAY BUT A `u32` ARRAY
# WITH FOUR FIELDS PER WORD, AND EVERY ACCESS IS A WORD ACCESS PLUS A
# SHIFT AND A MASK.
