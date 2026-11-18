<!-- FROM: tinybendygrad/mixin/rand.bend:1318 -->
# BLOCK:
# THE MEASURED MUTATION TABLE. Eight one-token edits through the interpreted lane, each
# diffed row-by-row against the unmutated output and reverted from a byte snapshot.
# Baseline: 55 printed rows, 32 shared with CPython and GREEN. Driver: this file is its own
# driver, so the mutation is a one-token edit here re-run under `gates/rand_census-gate.py`;
# the transcript is `gates/artifacts/rand_census-gate/bd.out`. Full table with row sets:
# `.agents/slop/notes/bend2-constraints.md`.
#
#  M1 `rd_mask`'s mask dropped (`n` -> `n - 1`)                2  st_max_g, st_zero_g
#  M2 `rd_p64`'s two args SWAPPED (reversed srcs)               1  tfb3_g
#  M3 `op_arange`'s trailing `.cast(dtype)` dropped             4  the four TOPOSORT rows
#  M4 `rd_bits_num`'s divisor 4 -> 2                            2  ref_bits_num23, ...223
#  M5 `rd_nmant`'s `case 32` arm dropped                        2  ref_nmant_f32, ref_shift_f32
#  M6 `rd_drop.arm`'s innermost arm 2 -> 1                      1  ref_drop_arm1
#  M7 `rd_p_ok`'s `<= 1` relaxed to `< 1`   [MOVED 0, THEN 1]   1  ref_dropout_p1 (see below)
#  M8 CONTROL: a comment                                       0  nothing, which is the point
#  M9 `rd_next`'s three reads moved BACK to the pre-write `ctr` 4  st_zero_g, st_six_g, st_after_g,
#                                                                    st_max_g -- AND NONE OF THEM
#                                                                    IS A `_v` ROW (see below)
#  M10 M9 PLUS `rd_next.v` transcribed against the same pre-write 7  the 4 `_g` rows AND st_six_v,
#      counter -- THE PORT AS IT STOOD                                  st_wrap_v, st_max_v
#
