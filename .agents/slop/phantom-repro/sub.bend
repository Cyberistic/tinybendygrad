import Base

# ===========================================================================
# The SHAPE of the substrate the four lanes imported, reduced to what the
# phantom def touched. Field names and arities are copied from
# tinybendygrad/uop/ops.bend (Op:169, Const:807, Tag:897, Arg:1045, Arena:1103,
# Found:2422, UOp.new:2442) so the message bend prints is the message the
# sweep recorded.
#
#   `Arg`  is ANone{} | ... | APy{v: Const} | ...     ops.bend:1045
#   `Const` is CBool{b: Bool} | CInt{..} | CFloat{..}  ops.bend:807
#
# so a `CBool` passed where an `Arg` is declared is `expected : Arg /
# observed : Const` -- by construction, and for the same reason the real lane
# died.  Nothing here is invented; it is the smallest thing that can carry the
# same error.
# ===========================================================================

type Op is Data:
  OpsCONST{}

type Const is Data:
  CBool{b: Bool}

type Arg is Data:
  ANone{}
  APy{v: Const}

type Tag is Data:
  TNone{}

type Arena is Data:
  Arena{nodes: List<&2, U32>}

type Found is Data:
  Found{ar: Arena, i: U32}

def Arena.empty() -> Arena:
  Arena{Nil{}}

def UOp.new(+ar: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag) -> Found:
  Found{ar, 0}

# ---------------------------------------------------------------------------
# THE PHANTOM.  This def is the entire cause of four lane deaths and it exists
# in NO other file.  phantom-run.py DELETES it before the victims are re-run,
# which is what makes the earlier error message name a def that is not on the
# tree.
# ---------------------------------------------------------------------------
def t_const_bool_int_splits() -> Bool:
  +u = UOp.new(Arena.empty(), OpsCONST{}, Nil{}, CBool{True{}}, TNone{})
  True{}

# The REACHABLE edge from a victim file into the phantom. Bend checks types
# lazily, so an importer that never reaches `t_const_bool_int_splits` does not
# see it at all -- measured by phantom-run.py, and the reason four lanes died
# rather than fifty.
def run() -> Bool:
  t_const_bool_int_splits()

# A second entry point that does NOT reach the phantom. Used to measure
# reachability rather than import.
def run_unreachable() -> Bool:
  True{}