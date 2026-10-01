import Base

def add(a: U32, b: U32) -> U32:
  U32.add(a, b)

def d(+xs: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["acc=", U32.show(List.foldl(&2, U32, U32, add, xs, 0)),
                           " head=", U32.show(Maybe.default(&2, U32, List.head(&2, U32, xs), 99)),
                           " tail0=", U32.show(Maybe.default(&2, U32, List.head(&2, U32, List.tail(&2, U32, xs)), 99)),
                           " len=", Nat.show(List.length(&2, U32, xs))]))

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- d([1, 2, 3])
    # `List.append(&2, U32, xs, ys)` is `xs ++ ys`. Build [9,8] by prepending one at
    # a time and watch whether it comes out [9,8] or [8,9].
    _ : Unit <- d(List.append(&2, U32, [9], [8]))
    _ : Unit <- d(List.append(&2, U32, [9], List.append(&2, U32, [8], [7])))
    _ : Unit <- d(List.reverse(&2, U32, [9, 8, 7]))
    _ : Unit <- d(List.reverse(&2, U32, List.append(&2, U32, [9], List.append(&2, U32, [8], [7]))))
    IO.print("")