import Base
import ../../../tinybendygrad/uop/ops.bend as O

# THE PORT'S LANE, in the shape `tinybendygrad/tensor.bend` gives it, and the
# PLANT for the "a metadata value that is a LIST, a DICT or a TENSOR" arm: the
# lane's value type is `Maybe<&2, O.Metadata>`, so those three are TYPE
# ERRORS and the compiler says so. CPython's lane is dynamically typed and
# accepts all three (MEASURED: a list, a dict and a Tensor are all stored
# verbatim in `all_metadata`), so this refusal is a DIVERGENCE and it is the
# port's answer: the type forbids what upstream's own annotation forbids
# (`_METADATA: _ContextVar[Metadata|None]`).

type MetaCell is Data:
  MetaCell{st: Maybe<&2, O.Metadata>}

def tn_meta_set(c: MetaCell, x: Maybe<&2, O.Metadata>) -> MetaCell:
  match c:
    case MetaCell{st}: MetaCell{x}

def plant_list() -> MetaCell:
  tn_meta_set(MetaCell{None{}}, Some{["a", "b"]})

def plant_dict() -> MetaCell:
  tn_meta_set(MetaCell{None{}}, Some{[("name", "x")]})

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("A LIST AND A DICT WERE ACCEPTED")
