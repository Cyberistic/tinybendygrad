import Base

# A SELF-CONTAINED copy of `mx_pool_f.go` / `mx_pool_f` from
# tinybendygrad/mixin/movement.bend, so this probe does not depend on
# helpers.bend -- which another agent had mid-edit (dirty, `nc_sign` reading `s`
# twice without `+`) at the moment of writing, and whose compile error blocks the
# whole import chain.  The commit is what this measures: `List.append` is
# `xs ++ ys`, so the two builds below differ ONLY in which slot the cons is in.

def mx_smax1(x: U32) -> U32: U32.max(1, x)
def mx_ofd(o: U32, s: U32, d: U32) -> U32: U32.sub(U32.mul(o, s), d)
def mx_isneg_ofd(o: U32, s: U32, d: U32) -> Bool: U32.is_lt(U32.mul(o, s), d)
def mx_ceildiv_s(neg: Bool, +num: U32, +amt: U32) -> U32:
  match neg:
    case True{}: U32.sub(0, U32.div(U32.sub(0, num), amt))
    case _: Bool.pick(U32, U32.is_eq(U32.mod(num, amt), 0),
                      U32.div(num, amt), U32.add(U32.div(num, amt), 1))
def mx_fs.of(neg: Bool, o: U32, s: U32, d: U32, i: U32) -> U32:
  mx_smax1(mx_ceildiv_s(neg, mx_ofd(o, s, d), i))
def mx_fs2(+o: U32, +s: U32, i: U32, +d: U32) -> U32:
  mx_fs.of(mx_isneg_ofd(o, s, d), o, s, d, i)

# the SHIPPED build: cons in slot 3, accumulator in slot 4
def f_prepend.go(o: List<&2, U32>, s: List<&2, U32>, i: List<&2, U32>, d: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match o s i d:
    case Nil{} Nil{} Nil{} Nil{}: acc
    case a <> t b <> u c <> v e <> r: f_prepend.go(t, u, v, r, List.append(&2, U32, [mx_fs2(a, b, c, e)], acc))
    case Nil{} _ _ _ : Nil{}
    case _ Nil{} _ _ : Nil{}
    case _ _ Nil{} _ : Nil{}
    case _ _ _ Nil{} : Nil{}

# the FIXED build: accumulator in slot 3, cons in slot 4
def f_append.go(o: List<&2, U32>, s: List<&2, U32>, i: List<&2, U32>, d: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match o s i d:
    case Nil{} Nil{} Nil{} Nil{}: acc
    case a <> t b <> u c <> v e <> r: f_append.go(t, u, v, r, List.append(&2, U32, acc, [mx_fs2(a, b, c, e)]))
    case Nil{} _ _ _ : Nil{}
    case _ Nil{} _ _ : Nil{}
    case _ _ Nil{} _ : Nil{}
    case _ _ _ Nil{} : Nil{}

def show.go(xs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  List.foldl(~&2, ~U32, ~List<&2, String>,
    (a: List<&2, String>) => (x: U32) => List.append(&2, String, a, [U32.show(x)]), xs, acc)

def show(xs: List<&2, U32>) -> String: String.join(show.go(xs, Nil{}), ",")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["uni    prepend=", show(f_prepend.go([3,3],[2,2],[8,8],[1,1], Nil{})),
                            " append=", show(f_append.go([3,3],[2,2],[8,8],[1,1], Nil{}))]))
    IO.print(String.concat(["nu2    prepend=", show(f_prepend.go([3,5],[1,2],[2,3],[1,1], Nil{})),
                            " append=", show(f_append.go([3,5],[1,2],[2,3],[1,1], Nil{}))]))
    IO.print(String.concat(["nu3    prepend=", show(f_prepend.go([9,2,7],[1,3,1],[4,5,2],[1,1,1], Nil{})),
                            " append=", show(f_append.go([9,2,7],[1,3,1],[4,5,2],[1,1,1], Nil{}))]))