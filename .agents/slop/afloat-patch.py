#!/usr/bin/env python3
"""afloat-patch.py -- rebuild this unit's `uop/ops.bend` edits as a RE-APPLIABLE PATCH.

WHY THIS FILE EXISTS. A concurrent unit overwrote the live `tinybendygrad/uop/ops.bend`
mid-run -- twice, with different content -- and the version that landed is missing BOTH
this unit's four `afloat_*` rows AND the earlier `ABlob` false-intern fix
(`eq_arg.ABlob(y: Arg, +n: U32)` comparing a LENGTH). It does not compile:
`ops.bend:6475` matches on `DRng`, which is declared nowhere. Per `agent-core.md` and
`notes/bend2-constraints.md` R-6 this unit does NOT write to that file while another unit
owns it, so the work is reconstructed here instead and handed over as a patch.

    .venv/bin/python .agents/slop/afloat-patch.py          # write the patch + the file
    git apply -p1 .agents/slop/afloat-ops-bend.patch        # once ops.bend is back

THE BASE IS AN ASSERTED HASH, NOT A PATH. `ops-blob-fixed.pristine.bend` and
`ops-blob-on.bend` are both `d5c1174eb9b45a8a8ac1f197c6268101`, which is byte-for-byte
the tree this unit started from -- hash asserted below, so a snapshot somebody else has
refreshed cannot silently become the base. The patch is `diff -u` against THAT file, so
it applies to the blob-fixed tree and not to a pre-blob-fix one: `eq_arg.ABlob` must
already read `+bs: List<&2, U32>`.
"""
import difflib
import hashlib
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
BASE = HERE / 'ops-blob-fixed.pristine.bend'
BASE_MD5 = 'd5c1174eb9b45a8a8ac1f197c6268101'
OUT_BEND = HERE / 'afloat-ops-bend.bend'
OUT_PATCH = HERE / 'afloat-ops-bend.patch'

AFLOAT_COMMENT_OLD = """def eq_arg.AFloat(y: Arg, +f: F32) -> Bool:
  match y:
    case AFloat{y1}: F32.is_eq(f, y1)
    case _: False{}
"""

AFLOAT_COMMENT_NEW = """# IEEE EQUALITY IS CORRECT HERE, AND `F32.bits` WOULD BE A REGRESSION. `eq_const.CFloat`
# one hundred lines up compares `F32.bits` and is right, so this arm LOOKS like the
# same bug. It is the OPPOSITE bug, and the difference is the PYTHON CLASS of the
# element `ops.py:201`'s key holds -- the key is
# `(op, src, arg, tag, type(arg))` and each element is compared with ITS OWN `__eq__`:
#
#   * `dtype.py:8-23` `class ConstFloat(float)` says in its own docstring that it
#     "distinguishes -0.0 from 0.0 and where nan == nan", and it overrides BOTH
#     `__eq__` (line 16) and `__hash__` (line 21, `hash(self.bits)`). So a CONST's
#     arg compares BITWISE -- which is why `eq_const.CFloat` is `F32.bits`.
#   * `AFloat` is the BARE `float`. It overrides nothing, so its hash is
#     `hash(-0.0) == hash(0.0)` and its equality is IEEE, and CPython therefore
#     interns `0.0` and `-0.0` as ONE key.
#
# MEASURED, live, on both trees this gate can select, by CALLING
# `.agents/slop/afloat-probe.py` (and by the four `afloat_*` rows of
# `.agents/slop/ops-oracle.py`, which are the same measurement as a gate):
#     UOp(Ops.CONST, arg=0.0)   is UOp(Ops.CONST, arg=-0.0)         -> True,  1 node
#     two DISTINCT float('nan') with the SAME 0x7fc00000 payload     -> False, 2 nodes
#     UOp(Ops.CONST, arg=1.5)   is UOp(Ops.CONST, arg=1.5)         -> True,  1 node
#     UOp(Ops.CONST, arg=1.5)   is UOp(Ops.CONST, arg=2.5)         -> False, 2 nodes
#     `type(arg)` keeps an `int` 0 and a `float` 0.0 apart           -> False, 2 nodes
# A `F32.bits` comparator inverts BOTH discriminating cells: it would split the signed
# zeros CPython joins and merge the two NaNs CPython keeps apart. THE ONE CELL NO
# VALUE-BASED PORT CAN REPRODUCE is the SAME NaN object twice, which interns in
# CPython (1 node -- `lookdict` short-circuits on pointer identity) and is False under
# `F32.is_eq`. That is a fact about Python object IDENTITY rather than about the float,
# so there is deliberately no row for it: a row would have to lie about one or the other.
def eq_arg.AFloat(y: Arg, +f: F32) -> Bool:
  match y:
    case AFloat{y1}: F32.is_eq(f, y1)
    case _: False{}
"""

AFLOAT_ROWS_OLD = """def s_blob_sweep_count() -> String:
  U32.show(U32.sub(Arena.next(blob_sweep_ar.go(blob_sweep_blobs(), Arena.empty())), 1))
"""

AFLOAT_ROWS_NEW = AFLOAT_ROWS_OLD + """
# ---------------------------------------------------------------------------
# AFLOAT -- `Arg`'s BARE-float arm, the OTHER half of the intern key. ops.py:201.
#
# The measurement and the reason `F32.is_eq` is right here and `F32.bits` would be a
# regression are the comment on `eq_arg.AFloat` above; this block is the GATE for it.
# `AFloat` has no constructor anywhere in the tree -- `uop/upat.bend:418` and
# `uop/render.bend:717` only READ it, and its one would-be builder `_frompy` is
# `TODO(p3)` at :4318 -- so no interning fixture can reach the arm the normal way and
# the comparator was untested rather than unreachable. These rows intern two
# `AFloat`s on ONE arena through `UOp.new`, so the answer is IDENTITY OF THE TWO
# INDICES and not `eq_arg` read directly: `blob_same` above says why, and this is
# the same rule.
# ---------------------------------------------------------------------------
def afloat_same(f1: F32, f2: F32) -> Bool:
  +u = UOp.new(Arena.empty(), OpsCONST{}, Nil{}, AFloat{f1}, TNone{})
  +v = UOp.new(Found.ar(u), OpsCONST{}, Nil{}, AFloat{f2}, TNone{})
  U32.is_eq(Found.i(u), Found.i(v))

# THE DISCRIMINATING CELL. `0.0` and `-0.0` are `0x00000000` and `0x80000000` and
# CPython interns them as ONE key; a bit comparator answers False here and splits it.
def t_afloat_zeros_intern() -> Bool: afloat_same(0.0, F32.neg(0.0))

# THE COUNTER-CELL. Two NaNs of the same payload, IEEE-unequal, and CPython keeps two
# nodes; a bit comparator answers True here and merges them. `F32.div(0,0)` is the
# file's NaN, the same construction `t_float_nan_interns` uses.
def t_afloat_nan_distinct_intern() -> Bool: afloat_same(F32.div(0.0, 0.0), F32.div(0.0, 0.0))

# THE TWO CONTROLS, and they are what make the two cells above mean something: a
# comparator that answered False for every float would satisfy the NaN row alone, and
# one that answered True for every float would satisfy the zeros row alone.
def t_afloat_same_intern() -> Bool: afloat_same(1.5, 1.5)

def t_afloat_distinct_intern() -> Bool: afloat_same(1.5, 2.5)
"""

MAIN_OLD = """row("blob_sweep", t_blob_sweep())
    srow("blob_sweep_count", s_blob_sweep_count())
"""

MAIN_NEW = """row("blob_sweep", t_blob_sweep())
    srow("blob_sweep_count", s_blob_sweep_count())
    # --- THE BARE-FLOAT LANE. ops.py:201. `AFloat` is the intern key's float half and
    # --- it compares IEEE, which is CORRECT for a bare `float` and wrong for the
    # --- `ConstFloat` in `eq_const.CFloat` -- see the comment on `eq_arg.AFloat`.
    row("afloat_zeros_intern", t_afloat_zeros_intern())
    row("afloat_nan_distinct_intern", t_afloat_nan_distinct_intern())
    row("afloat_same_intern", t_afloat_same_intern())
    row("afloat_distinct_intern", t_afloat_distinct_intern())
"""

EDITS = [
  ('the measured comment on `eq_arg.AFloat`', AFLOAT_COMMENT_OLD, AFLOAT_COMMENT_NEW),
  ('the four `afloat_*` row defs', AFLOAT_ROWS_OLD, AFLOAT_ROWS_NEW),
  ('the four `afloat_*` rows in `main`', MAIN_OLD, MAIN_NEW),
]


def main() -> int:
  raw = BASE.read_bytes()
  got = hashlib.md5(raw).hexdigest()
  if got != BASE_MD5:
    print(f"afloat-patch: REFUSING. {BASE.name} is {got}, not the {BASE_MD5} this unit "
          f"started from. Somebody refreshed the snapshot; re-derive the base before "
          f"applying anything.", file=sys.stderr)
    return 2
  base = raw.decode('utf-8')
  for name, old, new in EDITS:
    n = base.count(old)
    if n != 1:
      print(f"afloat-patch: REFUSING. Anchor for {name} matched {n} times, expected 1.",
            file=sys.stderr)
      return 2
    base = base.replace(old, new)
  if 'eq_arg.ABlob(y: Arg, +n: U32)' in base:
    print("afloat-patch: REFUSING. This base still compares an ABlob by LENGTH, so the "
          "patch would apply on top of the false-intern fix rather than after it.",
          file=sys.stderr)
    return 2
  OUT_BEND.write_text(base, encoding='utf-8')
  diff = difflib.unified_diff(BASE.read_text(encoding='utf-8').splitlines(True),
                              base.splitlines(True),
                              fromfile='a/tinybendygrad/uop/ops.bend',
                              tofile='b/tinybendygrad/uop/ops.bend')
  OUT_PATCH.write_text(''.join(diff), encoding='utf-8')
  print(f"afloat-patch: base md5 {BASE_MD5} ASSERTED")
  print(f"afloat-patch: wrote {OUT_BEND.name} ({len(base.splitlines())} lines, "
        f"{len(base) - len(BASE.read_text(encoding='utf-8')):+d} chars) and "
        f"{OUT_PATCH.name} ({len(OUT_PATCH.read_text().splitlines())} diff lines)")
  return 0


if __name__ == '__main__':
  sys.exit(main())