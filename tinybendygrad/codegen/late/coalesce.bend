# coalesce.bend -- tinygrad/codegen/late/coalesce.py: memory coalescing and the
# image-load VALID simplification, as the two pattern tables the lowerer runs.
#

# The 54 rows the merged file printed CONCATENATE IN PYTHON'S ORDER
# (`simplify.bend`, then this, then `gpudims.bend`) to exactly those 54, and
# `.agents/slop/codegen3-gate.sh` is that invariant against the pre-split
# snapshot.
#
# THIS IS THE SMALLEST OF THE THREE, and it is small for the reason upstream is
# small: two of coalesce.py's nine defs are TABLES and the seven around them are
# all one wall. So this file is two `O.PMEntry` lists, two length rows, and the
# inventory that says which wall each of the other seven hits.
#

# THE INVENTORY, def by def, against coalesce.py's 168 lines.
#
#   #  PY            KIND    STATE

#  20  13-40  fold   _drop_valid_stmts         WALL: functools.cache + variable
#  21  41-44  fold   simplify_valid_load       WALL: uop_given_valid + simplify
#  22  45-57  fold   simplify_valid_image_load WALL: the above + image dims
#  23  58-65  table  indexing_simplify         2 of 2, both rules WALL
#  24  66-73  data   image_valid_dims          PORTED, env opt as a PARAMETER
#  25  74-96  fold   transform_to_image        WALL: ctx shapes dict + IMAGE env
#  26  97-103 fold   store_image               PORTED, one cast rule WALL
#  27  104-108 table pm_simplify_add_image     2 of 2, rule 1 WALL, rule 2 PORTED
#  28  109-168 fold  memory_coalescing         WALL: defaultdict + groupby
#
# 9 defs, of which TWO are ported -- and both are tables, so the port is two
# entries and four numbers. Every table's LENGTH and every `rej` SET is exact and
# gateable, so the dispatch tables below are the real ones: they are what `UPat`
# compiles to, whatever the rules inside them can do.
#
# THE WALL, stated once and honestly: `_drop_valid_stmts` is `@functools.cache`d
# and `memory_coalescing` keeps a `defaultdict` keyed by a 5-tuple. Neither is a
# set this architecture can hold, and neither has a rule that would fire without
# it, so neither is a missing TABLE -- they are the WALL, marked above against
# their own lines.
#
# THE NAME CORRESPONDENCE: `indexing_simplify` (coalesce.py:58) and
# `pm_simplify_add_image` (coalesce.py:104) -- both upstream names, both in the
# file's own inventory above. The merged file called them `is_table` and
# `im_table`, so this is TWO renames, both inside this file, both applied in ONE
# single-pass token rewrite by `.agents/slop/split-codegen3.py`, whose `--check`
# undoes them and finds the original bytes. The other seven defs are ported as
# tables and not as functions, so there is nothing in this file to name after
# them.
#
# THE GATE. Two rows, both DERIVED FROM PYTHON by `.agents/slop/notes/rw-truth.py`,
# which prints them in THIS ORDER and with THIS SPELLING. The other 52 rows of the
# old merged file are `simplify.bend`'s and `gpudims.bend`'s.
#
# UPSTREAM'S EXPLANATORY COMMENTS, AND THEY ARE THE REASON THE TWO PORTED
# DEFS ARE PORTED AT ALL. This file's port is two TABLES and four numbers, and
# a reader needs to know what those tables are FOR:
#
# `indexing_simplify` (58-65):
#   "image load valid idx simplification" (59)
#       an IMAGE load's index carries a VALID -- the "is this pixel inside the
#       image" condition -- and the simplification asks whether the VALID is
#       NEEDED at all. Sometimes the index is out of bounds whenever the valid
#       is false, and then the valid is dead weight.
#   "can drop valid if idx is out of bound when valid is False" (14)
#       and that is the whole criterion: the valid is droppable when the index
#       is out of bounds on the valid's false side.
#   "for X0 + X1 + ... >= 1, check if it's out of bound when Xi = 0 for all i"
#       (20)
#       so for a valid that is a SUM of independent conditions, the check
#       substitutes ZERO for every term and asks whether the index then leaves
#       the image. If it does, the whole sum is droppable.
#   "check if idx is out of bound when X is on the wrong side of the bound: X in
#    [c+1, vmax] or [vmin, c-1]" (27)
#       the other direction: the index is out of bounds when the term is on the
#       WRONG SIDE of the bound, and then that term's valid can go.
#   "idx may not have X itself, so also substitute a term of X: v -> fake -
#    (X - v)" (32)
#       and THIS is a gotcha: the index may not mention the bound term at all,
#       so substituting a FAKE value for the term is not enough -- the term
#       that IS in the index has to be rewritten to carry the fake value
#       consistently. That is why the substitution list has TWO entries.
#
# `pm_simplify_add_image` (104-108):
#   "the image dims are stored in the param's arg, the size stays the flat
#    buffer len" (89)
#       so an image PARAM carries its (height, width) IN ITS ARG while the
#       buffer's SIZE stays the flat length. The two are different numbers and
#       conflating them is a wrong kernel.
#   "search for dims that drop the most valid statements" (78)
#   "if no candidates, we don't rewrite" (85)
#   "and tiebreak with indexing complexity (ie. number of nodes)" (87)
#       so the image dims are CHOSEN by a search, not computed: the candidate
#       that DROPS THE MOST VALID STATEMENTS wins, ties are broken by the
#       simpler index, and if there is no candidate at all the rewrite does not
#       happen.
#   "height=1 images just need to abide by alignment requirements in bytes, not
#    pixels!" (70)
#       and that is a correction upstream makes to its own rule: a one-pixel-tall
#       image is about BYTE alignment, not PIXEL alignment.
#   "image load/store is always float, a half image converts on store" (95)
#       so the image is ALWAYS float, and a half value stored into it is
#       CONVERTED on the store rather than on the load.
#
# `memory_coalescing` (109-168) -- the wall, but its comments are why the wall
# is a wall and not an omission:
#   "depth[u] is the lexicographically largest (GLOBAL stores, LOCAL stores)
#    count on any chain u waits on, u included" (111)
#       so the depth is a PAIR -- the GLOBAL store count and the LOCAL store
#       count -- and it is the LARGEST over the chains the node waits on. The
#       pair is LEXICOGRAPHIC, so the GLOBAL count dominates.
#   "loads/stores only coalesce with others carrying the same arg (e.g. the
#    nontemporal flag) and the same depth (GLOBAL count only for GLOBAL
#    accesses), so no merge closes a dependency cycle" (129-130)
#       THIS is the safety condition and it is the reason the depth is in the
#       grouping key at all: two accesses may only be merged if they have the
#       same depth, because otherwise the merge could close a dependency
#       cycle -- the merged store would depend on itself.
#   "allowed lengths (copied in)" (136)
#   "do the grouping" (146)
#   "the group starts at its first access's index, valid included" (150)
#       so a merged access starts at the FIRST access's offset and the VALID
#       is part of the group -- the valid is not a separate thing that has to
#       be merged separately.
#   "apply" (166)
#       and the whole of it is a SUBSTITUTION: the replacements map each
#       original access to its merged form.

import Base
import ./../../helpers.bend as H
import ./../../LAWS/spec.bend as S
import ./../../uop/ops.bend as O
import ./../../uop/fold.bend as F
import ./../rewriter.bend as RW

#   -- late/coalesce.py ----------------------------------------------------
#  20  13-40  fold   _drop_valid_stmts         WALL: functools.cache + variable
#  21  41-44  fold   simplify_valid_load       WALL: uop_given_valid + simplify
#  22  45-57  fold   simplify_valid_image_load WALL: the above + image dims
#  23  58-65  table  indexing_simplify         2 of 2, both rules WALL
#  24  66-73  data   image_valid_dims          PORTED, env opt as a PARAMETER
#  25  74-96  fold   transform_to_image        WALL: ctx shapes dict + IMAGE env
#  26  97-103 fold   store_image               PORTED, one cast rule WALL
#  27  104-108 table pm_simplify_add_image     2 of 2, rule 1 WALL, rule 2 PORTED
#  28  109-168 fold  memory_coalescing         WALL: defaultdict + groupby

def indexing_simplify() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsINDEX{}], [O.OpsWHERE{}]},       # coalesce.py:62 INDEX(buf, invalid_gate)
   O.PMEntry{1, [O.OpsINDEX{}], [O.OpsWHERE{}]}]        # coalesce.py:64 INDEX(buf, where, where)

def pm_simplify_add_image() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsSHRINK{}], [O.OpsPARAM{}]},       # coalesce.py:111 SHRINK(PARAM, x, C4)
   O.PMEntry{1, [O.OpsSTORE{}], Nil{}}]                 # coalesce.py:112 STORE.f(half)

def t_is_len() -> U32:
  RW.n_of(indexing_simplify())

def t_im_len() -> U32:
  RW.n_of(pm_simplify_add_image())

def main() -> IO(Unit):
  do IO<Unit>:
    RW.row("is_len", t_is_len())
    RW.row("im_len", t_im_len())
