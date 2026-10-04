# coalesce.bend -- tinygrad/codegen/late/coalesce.py: memory coalescing and the
# image-load VALID simplification, as the two pattern tables the lowerer runs.
#
# ---------------------------------------------------------------------------
# ONE OF THREE. `codegen/rewriter.bend` was ONE file for `simplify.py` +
# `late/coalesce.py` + `gpudims.py`; the 1:1 ruling -- one `.bend` per upstream
# `.py`, AT THE SAME PATH, no merging and no prefixes standing in for a directory
# -- made it three, and this is `late/coalesce.py`'s. The 54 rows the merged file
# printed CONCATENATE IN PYTHON'S ORDER (`simplify.bend`, then this, then
# `gpudims.bend`) to exactly those 54, and `.agents/slop/codegen3-gate.sh` is that
# invariant against the pre-split snapshot. The cut itself is
# `.agents/slop/split-codegen3.py`, which moved every body by LINE RANGE.
#
# THIS IS THE SMALLEST OF THE THREE, and it is small for the reason upstream is
# small: **two of coalesce.py's nine defs are TABLES and the seven around them are
# all one wall.** So this file is two `O.PMEntry` lists, two length rows, and the
# inventory that says which wall each of the other seven hits.
#
# ---------------------------------------------------------------------------
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
# THE WALL, stated once and honestly: **`_drop_valid_stmts` is `@functools.cache`d
# and `memory_coalescing` keeps a `defaultdict` keyed by a 5-tuple.** Neither is a
# set this architecture can hold, and neither has a rule that would fire without
# it, so neither is a missing TABLE -- they are the WALL, marked above against
# their own lines.
#
# ---------------------------------------------------------------------------
# THE NAME CORRESPONDENCE: `indexing_simplify` (coalesce.py:58) and
# `pm_simplify_add_image` (coalesce.py:104) -- both upstream names, both in the
# file's own inventory above. The merged file called them `is_table` and
# `im_table`, so this is TWO renames, both inside this file, both applied in ONE
# single-pass token rewrite by `.agents/slop/split-codegen3.py`, whose `--check`
# undoes them and finds the original bytes. The other seven defs are ported as
# tables and not as functions, so there is nothing in this file to name after
# them.
#
# ---------------------------------------------------------------------------
# THE GATE. Two rows, both DERIVED FROM PYTHON by `.agents/slop/notes/rw-truth.py`,
# which prints them in THIS ORDER and with THIS SPELLING. The other 52 rows of the
# old merged file are `simplify.bend`'s and `gpudims.bend`'s.

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
