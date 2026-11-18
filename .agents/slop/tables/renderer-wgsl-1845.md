<!-- FROM: tinybendygrad/renderer/wgsl.bend:1845 -->

# THE MUTATION TABLE. Measured 2026-10-02 with
# `.agents/slop/wgsl-mutate.py`, one textual edit at a time, each row diffed
# against the unmutated 168. "moved" is the number of rows that changed; the
# driver prints which.
#
#   M1  is_packed ANDs addr_is_reg instead of negating it   36
#   M2  is_packed drops the `dt != half` clause               6
#   M3  is_packed drops the `itemsize < 4` clause           11
#   M4  bd_go conses instead of appends                      3  rk_bindings rk alu rk mixed
#   M5  pt.go appends instead of conses                      3  rk_body rk alu rk mixed
#   M6  u32_show appends instead of conses                   2  local_max rk_sz mixed
#   M7  (the no-op control)                                    0
#   M8  the colon after the name gains a space               3
#   M9  var<storage> loses ,read_write                       3
#   M10 a packed buffer is not atomic                       FAIL  compile
#   M11 atomicLoad loses its &                                0  <-- BLIND SPOT
#   M12 the barrier loses its semicolon                       0  <-- BLIND SPOT
#   M13 WHERE renders the ternary, not select                1
#   M14 render_cast's unsigned narrow loses its `u`          2
#   M15 render_cast's signed narrow stops sign-extending     2
#   M16 the f16 enablement is dropped                       FAIL  compile
#   M17 (the INFINITY colon)                                  -  pattern not found
#   M18 the nan() helper leaves the prologue                  3
#   M19 the workgroup_size fallback is 0, not 1               1
#   M20 the local-size sort never compares                    0  <-- BLIND SPOT
#   M21 the hoist looks for var<uniform>                      1
#   M22 the hoisted line is not lstripped                     1
#   M23 the binding number starts at 0, not 1                 3
#   M24 the vec3 builtins lose their type                    3
#   M25 elems is the itemsize, not 4/itemsize                 5
#   M26 width is 4*itemsize, not 8*itemsize                  12
#   M27 wmask xors with 0, not 0xFFFFFFFF                    6
#   M28 the nan threshold shifts by exp, not mant             4
#   M29 the nan mask is 2^bits, not 2^(bits-1)                3
#   M30 type_map sends uchar to i32                           3
#   M31 (the workitem axis letter)                            -  pattern not found
#   M32 supported_dtypes always includes half                 1
#   M33 _render_dtype spells f32, not the storage class 2
#   M34 ssimp's CAST-of-CONST arm is dropped             2
#   M35 the f16 test compares against float             2
#   M36 a global buffer takes the var<uniform> arm       3
#
# M37-M54 AND P1-P9 ARE `string_rewrite`, MEASURED 2026-10-14 BY
# `gates/wgsl_render_census-mutate.py`, which mutates a COPY of this file beside
# the original (a copy anywhere else cannot even warm: the imports are relative
# to the file's own path) and runs the whole gate per mutation. That harness is
# the second half of the gate: a mutation that moves nothing is a claim nothing
# checks. The numbers below are the ROWS THAT MOVED, one per mutation.
#
#   M37 sr_buchar's mask is 0xFF00                1  sr buchar
#   M38 sr_bchar's shift is <<8                   1  sr bchar
#   M39 sr_bshort stops sign-extending            1  sr bshort
#   M40 sr_bany drops the type argument           1  sr bany
#   M41 sr_bushort's half arm loses its vec2      1  sr bushort half
#   M42 sr_rmw's atomicAdd loses its newline      1  sr rmw nv
#   M43 sr_lgate's select is a ternary            2  sr lgate packed sr lgate plain
#   M44 sr_index never strips parens              1  sr index add
#   M49 sr_idx's guard is dropped                 1  sr idx plain
#   M50 sr_ci32 truncates to 64 bits             2  sr ci32 4294967295 sr ci32 4294967296
#   M51 sr_cuint forgets the u32 mask             2  sr cuchar -1, sr cuchar 4294967296
#   M52 sr_buffer drops the space after the colon 3  sr buffer global/local/reg
#   M53 ssimp walks ONE cast, not the chain       2  rk_sz mixed rk mixed
#   M54 type_map's KeyError arm answers nothing   1  type_map double, via the PIN check
#
# M55-M63 are the seventeen patterns, one edit per discriminating field, and each
# moves EXACTLY ONE `srneg` row -- the row for the rule it breaks. MEASURED
# 2026-10-14 on this tree, one row each, and they are what makes the seventeen
# `NOMATCH`s load-bearing rather than seventeen tokens nobody could tell apart.
#
#   M55 sr_bhalf ANDs half with src=, so it ORs   1  srneg 6
#   M56 sr_pick_bitcast drops rule 6's src=       1  sr pick bitcast (11 -> 6)
#   M57 sr_pick_store forgets packed_rmw's AND    0  BLIND SPOT, see THE PIN
#   M58 sr_rmw forgets packed_rmw's AND           0  BLIND SPOT, see THE PIN
#   M59 sr_store accepts a 3-src GATED store      1  srneg 15, DROPS THE GATE AGAIN
#   M60 sr_buffer forgets the BUFFER op           1  srneg 5
#   M61 sr_load accepts any src count             1  srneg 13
#   M62 sr_idx forgets the CAST dtype             1  srneg 0
#   M63 sr_neg accepts float32 as an unsigned     1  srneg 1
#   M64 sr_rmw_cast forgets the CAST              1  sr rmw bare
#   M65 sr_rmw_cast refuses every buffer          2  sr pick store, sr rmw nv
#
# M59 IS THE DANGEROUS ONE NOW, and it is worth reading with M64: M59 reinstates a
# SILENT WRONG ANSWER rather than an over-firing -- a gated store whose gate is
# dropped -- and it shows in a diff of the two lanes' row NAMES only.
# M64 AND M65 ARE THE PIN'S OWN, and they are the two mutations that say the new
# predicate is load-bearing: M64 (`sr_rmw_cast` forgets the CAST) moves `sr rmw
# bare`, and M65 (`sr_rmw_cast` refuses every buffer) moves `sr pick store` AND
# `sr rmw nv`.
#   P1 the port drops rule 16's whole row group   DEAD  5, "207 rows" expected
#   P2 the port drops ONE row from a group        DEAD  5, "207 rows" expected
#   P3 the ORACLE drops one rule's rows          REFUSED 3, "207 rows" expected
#   P4 the port RENAMES a row (same count)        1  sr bushort half
#   P5 the pins lose a pinned divergence          1  code_for_op LOAD
#   P6 a pin's PORT VALUE is edited               1  type_map double, "appears 0 times"
#   P7 the port's fixture axis drifts              0  BLIND SPOT, see THE PIN
#   P8 the oracle's fixture axis drifts            0  fixtures_hold: SR_CI
#   P9 the port DUPLICATES a row name              1  sr bany
#
# P1-P9 ARE THE POPULATION MUTATIONS, and they are the ones this file could not
# have found by reading. P7 and P8 drift the `r_cu1`/`r_ci1` AXIS -- the `(name,
# hi, lo)` triples `fixtures_hold` reads out of this text -- and P7 moves a row
# while P8 moves NOTHING and is caught only by the axis check, which is the
# answer to "an oracle that covers whatever the port happens to do is not an
# oracle". P9 keeps the row COUNT at 207 and still goes red, by NAME.
#
# M51 is the one a reading missed and a mutation caught. `sr_cuint`'s
# `& 0xFFFFFFFF` is only observable on a weakint CONST whose HIGH WORD is set
# and whose low word reads as non-negative; the original three axis rows all had
# `hi == 0`, so replacing `masked(v)` with `v` left every one of them unchanged
# and the gate was GREEN on a mutation. The `4294967296` row is the fix and it
# was added because the mutation table said so, not because the code looked
# wrong. IT NOW MOVES TWO ROWS, and the second one is the PIN's: rule 3 has no
# negative arm, so a weakint CONST of -1 is masked to `4294967295u` and the mask
# is observable on it too.
#
# the PIN, and the three blind spots it opened.
#
# `tinygrad/renderer/wgsl.py` MOVED under this port, and TWO of its changes
# touch the rows: `string_rewrite`'s rule 3 lost its negative-const arm and
# rule 14's STORE pattern gained a `CAST` on its buffer. MEASURED, the two
# patterns are INVERTED over the two nodes -- the pre-pin rule 14 answered
# `atomicAnd(&B[1],W);` on `STORE(INDEX, AND)` and NOTHING on `STORE(CAST,
# AND)`, and the pinned one answers NOTHING on the first and `atomicAnd(&B[1],
# W);` on the second -- so this file's `sr rmw bare` row is a REFUSAL now, and
# `sr rmw nv` still renders the pair.
#
# the three blind spots are all the same one: the rule-14 predicate is now three
# clauses and no fixture isolates the second. `sr_pick_store` and `sr_rmw` test
# the src COUNT, the VALUE's op (`Ops.AND`) and the BUFFER's op (`Ops.CAST`),
# and the oracle's three rule-14 fixtures are `rmw nv` (AND, CAST), `rmw bare`
# (AND, INDEX) and `rmw plain` (CONST, INDEX): every one of them is refused by
# the CAST clause or by the AND clause or by BOTH, so removing EITHER clause
# alone changes no row. MEASURED 2026-10-22: M57 and M58 move 0 rows, where
# they moved 1 each before the pin. THE FIX IS AN ORACLE FIXTURE, not a port
# fix -- a fourth rule-14 node whose buffer IS a CAST and whose value is NOT an
# AND -- and it needs a row on both sides.
#
# P7 is the same shape from the other end. Rule 3 renders a weakint CONST of -1
# and one of 4294967295 as the SAME `4294967295u`, so drifting the `-1` axis
# entry's high word changes no row: MEASURED, P7 moves 0 rows where it moved 1.
# The AXIS still carries -1 because the WEAKINT value is still a different one,
# and `fixtures_hold` compares the axis and not the rendering -- so the axis is
# right and the MUTATION is blind.
#
# THE PLANTS, and they are the same harness the mutation table uses: a COPY of
# this file beside the original, one edit, and the rows that moved.
#
#   PLANT A  rule 3 regains the pre-pin negative arm    1  sr cuchar -1
#   PLANT B  `sr_rmw_cast` always true (pre-pin rule 14) 1  sr rmw bare
#
# A PLANT THAT MOVES NOTHING IS A HOLE, so A and B are the two claims that the
# pin's two changes are load-bearing, and they are the two the gate's lane diff
# would otherwise have caught silently.
#
# WHAT THE TABLE SAYS, and the three things it caught that the rows did not.
#
# M1 IS THE ONE THAT MATTERS. It is the bug this file SHIPPED with for an hour:
# `is_packed` ANDed `addr_is_reg` where wgsl.py:32 negates it, so the predicate
# said "packed iff REGISTER" and the entire packed path -- `atomic<u32>`,
# `atomicLoad`, the `atomicAnd`/`atomicAdd` read-modify-write -- was dead, because
# no buffer a shader reads is a register. It typechecked. Every `pf_*` row, every
# `wmask` row and all 100-odd other rows stayed green. Only `rk mixed` moved, and
# only on one line of a 700-character module. the fixture class this file was
# MISSING IS A PREDICATE WITH NO ROW: `is_packed` had none, so no mutation could
# find it, and the 40 `is_packed`/`buf_map`/`packed_size` rows exist because of
# that. M1 now moves 36.
#
# M4, M5 AND M6 ARE THE ORDER MUTATIONS, and they are three rows each -- which is
# the localisation the brief asks for. `bd_go` and `pt.go` reach `String.join`
# and so must APPEND; `u32_show` and `ls_sz` are WALKED and so must PREPEND. Each
# wrong choice reverses a WHOLE SHADER and is invisible in a boolean.
#
# FIVE BLIND SPOTS LEFT, and they are the honest content of this table. TWO OF
# THEM ARE THE PIN'S -- M57, M58 and P7, and they are in THE PIN block above
# with the reason and the fix.
#
#   M11's BLIND SPOT IS GONE. It moved nothing because `render_load` had NO ROW
#   AT ALL -- it was ported, called by nothing in this file (the string rule that
#   calls it is `string_rewrite`, which was the wall), and ungated. `render_load`
#   now has FOUR rows, `sr lgate packed`, `sr lgate plain`, `sr load packed` and
#   `sr load plain`, and M43 moves two of them by mutating its one caller.
#   M12 still moves nothing: `barrier()` has a row, but M12's edit did not reach
#   it, and that is a property of the EDIT and not of the row.
#   M20 moves nothing because `ls_ins`'s no-compare arm appends, and the fixture's
#   WALK order (l0, l1) already agrees with its SORT order. The fixture needs a
#   case whose walk order DIFFERS from its sort order -- a `uops` list holding l1
#   before l0 -- and then M20 says `2,8`. That is the brief's two-rules-claim-one-
#   node trap in its purest form, and this table is the evidence that the trap is
#   still open here. the oracle has the case and asserts it (`UOPS_MIXED_SWAPPED`
#   in `gates/wgsl_render_census-oracle.py`, whose `assert` names "the sort is not
#   load-bearing"), so the gap is on the PORT's side only.
#   M7 is the control: an edit that changes nothing must move nothing.
#
# TWO MUTATIONS FAIL TO COMPILE rather than moving rows, and that is information
# too: `buf_map`'s two arms must both be `String` (M10) and `rk_f16`'s arms must
# both be `String` (M16), so those two constants are pinned by the type system as
# well as by the text. Two more (M17, M31) did not find their pattern and are
# recorded as untested rather than as passing.
#
# WHAT IS STILL NOT GATED, stated as a boundary and not as an omission. The
# census compares each RULE'S ANSWER on a chosen fixture AND, since the patterns
# landed, whether the rule DECLINES a node CPython's own `UPat` declines -- the
# seventeen `srneg` rows, one per rule, each an EXACT MATCH rather than a pin
# because both sides print `NOMATCH`. Three things are still outside it.
#
# 1. `packed_rmw`'s INNER shape. `sr_pick_store` and `sr_rmw` test `Ops.AND`,
#    which is `packed_rmw`'s outer op and the whole of what distinguishes a
#    read-modify-write from a plain store, and the pin's THIRD predicate -- the
#    store's buffer being a CAST -- which is `sr_rmw_cast`; but
#    `AND(LOAD(CAST(b, u32)), wmask)` -- the `& UPat.var("wmask")` is an Ops.AND
#    and not a bind -- is still unported, and `prw_of` is still the def that
#    names it and calls nothing. A CONST spliced onto an `AND` of the wrong
#    shape would still pass.
# 2. RULES 0, 2, 3 AND 4 SHARE AN OP and their dtypes are NOT all disjoint --
#    rule 0 is `uint32` and rule 3 is `uint32 | uint16 | uint8` -- so they divide
#    on src[0]'s op as well, and the ORDER between them is untested because they
#    cannot both match one node. Same for rules 12 and 13 (`sr pick load` prints
#    the indices anyway, because the fact is worth having).
# 3. THE SPELLING OF EACH `srneg` NODE is the port's own. The oracle ASSERTS, on
#    CPython's real node, that each `UPat` rejects it -- so the refusal is real on
#    that side -- but the gate does not re-derive `srneg 6`'s target dtype from
#    the node and compare it to `S.uint32()` in this file. Both sides refusing is
#    checked; both sides refusing about the SAME node is not.
#
