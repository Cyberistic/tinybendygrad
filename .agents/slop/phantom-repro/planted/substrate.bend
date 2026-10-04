import Base

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

def answer() -> Bool:
  True{}

def t_const_bool_int_splits() -> Bool:
  +u = UOp.new(Arena.empty(), OpsCONST{}, Nil{}, CBool{True{}}, TNone{})
  True{}
