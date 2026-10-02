import Base

def str_le(a: String, b: String) -> Bool: String.is_lt(a, b)
def sort_strs(xs: List<&2, String>) -> List<&2, String>: List.sort(String, str_le, xs)

def order_at(o: List<&2, String>, +nm: String, +i: U32) -> U32:
  match o:
    case Nil{}: 0
    case +h <> +t: Bool.pick(U32, String.eq(h, nm), i, order_at(t, nm, U32.add(i, 1)))

def str_in(+nm: String, o: List<&2, String>) -> Bool:
  match o:
    case Nil{}: False{}
    case +h <> +t: Bool.or(String.eq(h, nm), str_in(nm, t))

def order_idx(+o: List<&2, String>, +nm: String) -> U32:
  Bool.pick(U32, str_in(nm, o), order_at(o, nm, 0), 999)

def o87() -> List<&2, String>:
  ["a0","a1","a2","a3","a4","a5","a6","a7","a8","a9","b0","b1","b2","b3","b4","b5","b6","b7","b8","b9",
   "c0","c1","c2","c3","c4","c5","c6","c7","c8","c9","d0","d1","d2","d3","d4","d5","d6","d7","d8","d9",
   "e0","e1","e2","e3","e4","e5","e6","e7","e8","e9","f0","f1","f2","f3","f4","f5","f6","f7","f8","f9",
   "g0","g1","g2","g3","g4","g5","g6","g7","g8","g9","h0","h1","h2","h3","h4","h5","h6","h7","h8","h9",
   "i0","i1","i2","i3","i4","i5","i6","i7","i8","i9","j0","j1","j2","j3","j4","j5","j6","zz"]

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(order_idx(o87(), "zz")))
