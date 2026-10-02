import Base

type T is Data:
  T{a: U32, b: U32}

def T.a(t: T) -> U32:
  match t:
    case T{a, b}: a

def T.b(t: T) -> U32:
  match t:
    case T{a, b}: b

# PROBE 1: `+name` in a list cons pattern
def mem(xs: List<&2, U32>, +x: U32) -> Bool:
  match xs:
    case Nil{}: False{}
    case h <> t: Bool.or(U32.is_eq(h, x), mem(t, x))

def nodup(xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}: True{}
    case h <> +t: Bool.and(Bool.not(mem(t, h)), nodup(t))

# PROBE 2: U32.shln with a U32.to_nat count, U32.shrn saturation
def p2(k: U32) -> U32: U32.or(U32.shln(k, 2n), 5)

# PROBE 3: a recursive def whose accumulator is a String built with ++
def p3(k: Nat, acc: String) -> String:
  match k:
    case 0n: acc
    case 1n+m: p3(m, String.concat([acc, "x"]))

# PROBE 4: a record of two lists, and a two-scrutinee match
type Kv is Data: Kv{ks: List<&2, U32>, vs: List<&2, U32>}

def Kv.ks(k: Kv) -> List<&2, U32>:
  match k:
    case Kv{ks, vs}: ks

def Kv.vs(k: Kv) -> List<&2, U32>:
  match k:
    case Kv{ks, vs}: vs

def zips(ks: List<&2, U32>, vs: List<&2, U32>) -> List<&2, U32>:
  match ks vs:
    case Nil{} Nil{}: Nil{}
    case Nil{} _     : Nil{}
    case _     Nil{} : Nil{}
    case k <> kt v <> vt: U32.add(k, v) <> zips(kt, vt)

def show_all(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}   : ""
    case h <> +t : String.concat([U32.show(h), ",", show_all(t)])

# PROBE 5: TWO self-calls in one arm, both on the same `+` list tail
def keeps(+want: U32, +cs: List<&2, U32>) -> List<&2, U32>:
  match cs:
    case Nil{}   : Nil{}
    case h <> +t : Bool.pick(List<&2, U32>, U32.is_eq(want, U32.and(h, 3)),
      List.append(&2, U32, keeps(want, t), [h]), keeps(want, t))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["nodup=", Bool.show(nodup([1, 2, 3])), " nodup2=", Bool.show(nodup([1, 2, 2])),
      " p2=", U32.show(p2(3)), " p3=", p3(4n, ""), " zip=", show_all(zips([1, 2], [10, 20])),
      " keeps=", show_all(keeps(2, [8, 9, 10, 11]))]))
