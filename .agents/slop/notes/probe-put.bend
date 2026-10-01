import Base

type Bf is Data:
  Bf{b: U32, f: U32, l: U32}

def Bf.b(x: Bf) -> U32:
  match x:
    case Bf{b, f, l}: b
def Bf.f(x: Bf) -> U32:
  match x:
    case Bf{b, f, l}: f
def Bf.l(x: Bf) -> U32:
  match x:
    case Bf{b, f, l}: l

def mem_bf_keep(hit: Bool, +e: Bf, acc: List<&2, Bf>, +i: U32) -> List<&2, Bf>:
  match hit:
    case True{}: List.append(&2, Bf, acc, [Bf{Bf.b(e), Bf.f(e), i}])
    case _: List.append(&2, Bf, acc, [e])

# PREPENDS, because the accumulator `mem_bf_keep` builds is already REVERSED:
# `List.append` puts the new entry at the head of the reversed list, which is the
# TAIL of the finished one. Appending here instead puts it at the tail of the
# reversed list -- the HEAD of the finished one -- and the whole table comes out
# back to front with the newest buffer first.
def mem_bf_ins(found: Bool, acc: List<&2, Bf>, b: U32, +i: U32) -> List<&2, Bf>:
  match found:
    case True{}: acc
    case _: List.append(&2, Bf, [Bf{b, i, i}], acc)

def mem_bf_done(found: Bool, acc: List<&2, Bf>, b: U32, +i: U32) -> List<&2, Bf>:
  List.reverse(&2, Bf, mem_bf_ins(found, acc, b, i))

def mem_bf_put.k(p: Nat, t: List<&2, Bf>, b: U32, i: U32, acc: List<&2, Bf>, found: Bool) -> List<&2, Bf>:
  mem_bf_put(p, t, b, i, acc, found)

def mem_bf_put(fuel: Nat, bs: List<&2, Bf>, +b: U32, +i: U32, acc: List<&2, Bf>, found: Bool) -> List<&2, Bf>:
  match fuel:
    case 0n: mem_bf_done(found, acc, b, i)
    case 1n+p:
      match bs:
        case Nil{}: mem_bf_done(found, acc, b, i)
        case +e <> t: mem_bf_put.k(p, t, b, i, mem_bf_keep(U32.is_eq(Bf.b(e), b), e, acc, i),
                                Bool.or(found, U32.is_eq(Bf.b(e), b)))

def mem_bf_touch(+bs: List<&2, Bf>, b: U32, i: U32) -> List<&2, Bf>:
  mem_bf_put((List.length(&2, Bf, bs) + 1n : Nat), bs, b, i, Nil{}, False{})

def at(xs: List<&2, Bf>, n: Nat) -> Bf:
  Maybe.default(&2, Bf, List.get(&2, Bf, xs, n), Bf{9, 9, 9})

def show(tag: String, +xs: List<&2, Bf>) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([tag, " -> ",
      U32.show(Bf.b(at(xs, 0n))), "/", U32.show(Bf.f(at(xs, 0n))), "/", U32.show(Bf.l(at(xs, 0n))), " ",
      U32.show(Bf.b(at(xs, 1n))), "/", U32.show(Bf.f(at(xs, 1n))), "/", U32.show(Bf.l(at(xs, 1n))), " ",
      U32.show(Bf.b(at(xs, 2n))), "/", U32.show(Bf.f(at(xs, 2n))), "/", U32.show(Bf.l(at(xs, 2n))), " ",
      U32.show(Bf.b(at(xs, 3n))), "/", U32.show(Bf.f(at(xs, 3n))), "/", U32.show(Bf.l(at(xs, 3n))), " ",
      U32.show(Bf.b(at(xs, 4n))), "/", U32.show(Bf.f(at(xs, 4n))), "/", U32.show(Bf.l(at(xs, 4n)))]))

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- show("rev ", List.reverse(&2, Bf, [Bf{3, 0, 0}, Bf{4, 1, 1}]))
    _ : Unit <- show("ins ", mem_bf_ins(False{}, Nil{}, 3, 0))
    _ : Unit <- show("done", mem_bf_done(False{}, Nil{}, 3, 0))
    _ : Unit <- show("put0", mem_bf_put(1n, Nil{}, 3, 0, Nil{}, False{}))
    _ : Unit <- show("put1", mem_bf_put(1n, Nil{}, 3, 0, Nil{}, False{}))
    _ : Unit <- show("r2  ", List.reverse(&2, Bf, [Bf{5, 2, 2}, Bf{4, 1, 1}, Bf{3, 0, 0}]))
    _ : Unit <- show("r2b ", List.reverse(&2, Bf, List.append(&2, Bf, [Bf{5, 2, 2}], [Bf{4, 1, 1}, Bf{3, 0, 0}])))
    _ : Unit <- show("t3  ", mem_bf_touch(Nil{}, 3, 0))
    _ : Unit <- show("t4  ", mem_bf_touch(mem_bf_touch(Nil{}, 3, 0), 4, 1))
    _ : Unit <- show("t5  ", mem_bf_touch(mem_bf_touch(mem_bf_touch(Nil{}, 3, 0), 4, 1), 5, 2))
    _ : Unit <- show("t56 ", mem_bf_touch(mem_bf_touch(mem_bf_touch(mem_bf_touch(Nil{}, 3, 0), 4, 1), 5, 2), 6, 2))
    _ : Unit <- show("t5@3", mem_bf_touch(mem_bf_touch(mem_bf_touch(mem_bf_touch(Nil{}, 3, 0), 4, 1), 5, 2), 5, 3))
    _ : Unit <- show("t57 ", mem_bf_touch(mem_bf_touch(mem_bf_touch(mem_bf_touch(mem_bf_touch(Nil{}, 3, 0), 4, 1), 5, 2), 6, 2), 7, 3))
    IO.print("")
