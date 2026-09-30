import Base

# THE ENGINE SHAPE. The rules GROW the arena, so if threading is real the
# second pass sees what the first left.
type Arena is Type:
  Nodes{items: List<&2, U32>}

type Rule is Type:
  R{use: (Arena -> Arena)}

# helpers first: a def may only call defs declared above it
def grow_prepend(a: Arena, v: U32) -> Arena:
  match a:
    case Nodes{items}: Nodes{v <> items}

def set_single(a: Arena) -> Arena:
  match a:
    case Nodes{items}: Nodes{[7]}

def r_double() -> Rule:
  R{a => grow_prepend(a, 2)}

def r_singleton() -> Rule:
  R{a => set_single(a)}

def a1() -> Arena:
  Nodes{Nil{}}

# ONE recursive def: no helper, no destructuring, no mutual recursion.
def engine_pass(rules: List<Rule>, a: Arena) -> Arena:
  match rules:
    case Nil{}:
      a
    case R{use} <> rest:
      engine_pass(rest, use(a))

def table() -> List<Rule>:
  [r_singleton(), r_double()]

def pass1(t: List<Rule>) -> Arena:
  engine_pass(t, a1())

def pass2(prev: Arena) -> Arena:
  engine_pass(table(), prev)

def len_of(a: Arena) -> U32:
  match a:
    case Nodes{items}: U32.from_nat(List.length(&2, U32, items))

def head_of(a: Arena) -> U32:
  match a:
    case Nodes{items}:
      match items:
        case Nil{}: 99
        case h <> _rest: h

def walk.items(items: List<&2, U32>, n: Nat, h: U32) -> U32:
  match items:
    case Nil{}: U32.add(U32.mul(U32.from_nat(n), 10), h)
    case x <> rest:
      walk.items(rest, 1n+n, x)

def walk(a: Arena, n: Nat, h: U32) -> U32:
  match a:
    case Nodes{items}: walk.items(items, n, h)

def show(a: Arena) -> U32:
  walk(a, 0n, 99)

# one fold: length and head in a single pass, so the arena is read once
# pass1: [] -> [7] -> [2,7].  pass2: [2,7] -> [7] -> [2,7].  length 2, head 2.
def two_passes() -> Arena:
  pass2(pass1(table()))

def main() -> U32:
  show(two_passes())