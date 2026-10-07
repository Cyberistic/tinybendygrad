# ops_bend MILESTONE 1 -- THE EXPECTED BYTES, WRITTEN BEFORE ANY RUN.
#
# Written by hand from IEEE-754 and little-endian layout. NOT transcribed from a
# run. Every value below is derived, and the derivation is next to the value so a
# reader can check it without running anything.
#
# THE KERNEL is `packet-tiny.txt`, the port's own fixture -- 13 uops, already
# CPython-verified and already the subject of the `bend_emit_tiny_match` row in
# `tinybendygrad/runtime/ops_bend.bend`. Its dataflow, read off the packet:
#
#     4: CONST weakint c:0            the scalar 0
#     5: CAST i32  <- 4               the global index, i32
#     6: INDEX f32  <- 2 5            buf1[0]
#     7: LOAD  f32  <- 6              a
#     8: INDEX f32  <- 3 5            buf2[0]
#     9: LOAD  f32  <- 8              b
#    10: INDEX f32  <- 1 5            buf0[0]
#    11: ADD   f32  <- 7 9           a + b
#    12: STORE void <- 10 11          buf0[0] = a + b
#
# so the kernel is `out[0] = buf1[0] + buf2[0]` over one work item, and the ONLY
# buffer the kernel writes is buffer 0. Buffers 1 and 2 must come back
# BIT-IDENTICAL, which is what makes the readback a test of the allocator and not
# just of the add.
#
# THE INPUT PATTERN, chosen so that a byte-order mistake cannot hide:
#     buf0 = 0xDEADBEEF   a sentinel that is NOT any f32 the add can produce, so a
#                         missing store is distinguishable from a wrong store
#     buf1 = 1.0
#     buf2 = 2.0
#
# THE f32 BIT PATTERNS, derived:
#     1.0f = 0x3F800000    sign 0 | exp 0x7F (127) | mantissa 0
#                          127 = 0x7F, bias 127, so 2^(127-127) = 2^0 = 1
#     2.0f = 0x40000000    sign 0 | exp 0x80 (128) | mantissa 0
#                          128-127 = 1, so 2^1 * 1.0 = 2
#     3.0f = 0x40400000    sign 0 | exp 0x80 (128) | mantissa 0x400000
#                          0x400000 = 2^22, mantissa 1.0 + 2^22/2^23 = 1.5,
#                          2^1 * 1.5 = 3
#     sum  = 0x40400000    1.0 + 2.0 = 3.0, and 3.0f is exact, so there is no
#                          rounding question to answer
#
# THE EXPECTED PACKET.out, three lines, `<nbytes> <hex-bytes>`, in the packet's own
# buffer order. The hex is LOW BYTE FIRST, because the wire is `<nbytes> <hex>`
# over a little-endian memoryview and `struct`/`to_mv` are both LE:
#
#     buffer 0   4 bytes   0x40400000 LE = 00 00 40 40   ->  "4 00004040"
#     buffer 1   4 bytes   0x3F800000 LE = 00 00 80 3F   ->  "4 0000803f"
#     buffer 2   4 bytes   0x40000000 LE = 00 00 00 40   ->  "4 00000040"
#
# and buffer 0's INPUT, for the record: 0xDEADBEEF LE = EF BE AD DE -> "4 efbeadde".
# Sentinel choice: 0xDEADBEEF is a signalling NaN as an f32 (exp 0xFF, mantissa
# 0x2AAB00 != 0), so it is a sentinel a correct ADD can never produce.
#
# ---------------------------------------------------------------------------
# WHAT THE MILESTONE IS, AND WHY THESE BYTES ARE THE WHOLE TEST
# ---------------------------------------------------------------------------
# A buffer allocated in Bend's own memory, written with the pattern above, run
# over by the kernel above, read back. `expected` is the WHOLE of PACKET.out.
# Anything less -- "the allocator returned something", "the trace had the right
# steps" -- cannot distinguish a kernel that ran from a kernel that was skipped.
#
# THE THREE FAILURE MODES THESE BYTES DISCRIMINATE, which is the load of the
# fixture rather than a decoration:
#   * no store at all            -> buffer 0 stays "4 efbeadde"
#   * store of the wrong operand -> buffer 0 is "4 0000803f" or "4 00000040"
#   * store to the wrong buffer  -> buffer 0 is the sentinel AND buffer 1 or 2 is
#                                   "4 00004040"
#   * byte-swapped hex on output -> "4 40400000" / "4 3f800000" / "4 40000000"
# All four are distinct strings, so a whole-line comparison separates them. A
# boolean over "did something change" would NOT: it is satisfied by all four.
#
# ---------------------------------------------------------------------------
# THE LOAD: THREE BUFFERS, 4 BYTES EACH. The denominator is stated because the
# disagreements count means nothing without it.
# ---------------------------------------------------------------------------
# buffers_in      = 3
# bytes_in        = 12
# bytes_out       = 12
# buffers_written = 1
# buffers_unchanged = 2
# ---------------------------------------------------------------------------
expected_packout_line_count = 3
expected_packout = "4 00004040
4 0000803f
4 00000040
"
expected_buffer0 = "4 00004040"
expected_buffer1 = "4 0000803f"
expected_buffer2 = "4 00000040"
expected_store_count = 1