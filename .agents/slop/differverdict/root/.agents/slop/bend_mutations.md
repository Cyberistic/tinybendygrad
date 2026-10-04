| # | edit | rows MOVED | first movers |
| --- | --- | --- | --- |
| M1 | Ns.at: drop the 1-based->0-based shift | 11 | bend_const_c, bend_const_f, bend_emit_cmp, bend_emit_cmp_match, bend_emit_cmp_ok, bend_emit_fconst... |
| M2 | src_text.go: append then reverse (the order bug this file shipped once) | 3 | bend_emit_cmp_match, bend_emit_fconst_match, bend_emit_tiny_match |
| M3 | lanes: drop the bool lane | 4 | bend_emit_cmp, bend_emit_cmp_match, bend_emit_cmp_ok, bend_lanefree_bool_not_lane |
| M4 | LANES_SORTED: reorder | 12 | bend_lane_sorted_is_literal, bend_refuse_bf16, bend_refuse_f16, bend_refuse_f64, bend_refuse_fp8e4m3fnuz, bend_refuse_fp8e5m2... |
| M5 | const_arg: every CONST is an int | 3 | bend_const_f, bend_emit_cmp_match, bend_emit_fconst_match |
| M6 | param_arg: letter always g | 0 |  |
| M6c | param_arg: keep the letter, drop the extent | 3 | bend_emit_cmp_match, bend_emit_fconst_match, bend_emit_tiny_match |
| M6b | letter.of: REG is a too | 1 | bend_letter_reg |
| M7 | vec_arg: every LOAD/STORE carries its width | 3 | bend_emit_cmp_match, bend_emit_tiny_match, bend_vec_1 |
| M8 | is_buf: accept the r letter too | 2 | bend_buf_l, bend_buf_r |
| M9 | buf_extent: the FIRST colon field | 3 | bend_extent_1024, bend_extent_16, bend_extent_4 |
| M10 | is_image_shape: any 3d shape is an image | 1 | bend_img_2_3_5 |
| M11 | idx_arg: BITCAST arm before the image arm | 0 |  |
| M12 | header: nbufs counts every line | 6 | bend_emit_cmp, bend_emit_cmp_match, bend_emit_fconst, bend_emit_fconst_match, bend_emit_tiny, bend_emit_tiny_match |
| M13 | rstrip1: never strip | 3 | bend_emit_cmp_match, bend_emit_fconst_match, bend_emit_tiny_match |
| M14 | has_local: True | 1 | bend_has_local |
| M15 | is_warp1: only X matters | 1 | bend_call_warp1 |
| M16 | Tr.step: drop the raise guard | 0 |  |
| M17 | letter_str: LOCAL prints a letter too | 1 | bend_letter_local |
| M18 | out_bufs: no dedup | 0 |  |
| M19 | a comment-only edit (THE CONTROL) | 0 |  |
| M20 | wire_dtype: void needs no lane either | 9 | bend_emit_cmp, bend_emit_cmp_match, bend_emit_cmp_ok, bend_emit_fconst, bend_emit_fconst_match, bend_emit_fconst_ok... |
# PIN NOT WRITTEN -- UNSTATED.  not re-run: 22/22 anchors present; no anchor work was needed and no run was performed here

# ======================================================================
# PIN -- what this table describes.  Written by pin-tables.py, 2026-10-04.
#   rev   the jj revision of the file the harness patched
#   file  sha256[:16] of that file.  Protects the MUTANT: it proves the edit
#         went into the file you meant.
#   rows  sha256[:16] of the ROW SET the counts were measured against.
#         Protects the REFERENCE, and it is the one that matters: a digest
#         over the mutant PROVABLY cannot see an operand-order defect, because
#         swapping `hi42`'s two shape args leaves `shape()`'s three fields
#         unchanged.  RULE C caught that twice in one day.
#   REPRODUCES  measured on 2026-10-04, TWICE, byte-identically.
