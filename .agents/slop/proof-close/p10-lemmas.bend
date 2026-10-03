import Base

def nat_add_zero(x: Nat) -> {Nat.add(x, 0n) == x : Nat}:
  match x:
    case 0n:
      {==}
    case 1n+p:
      +q = p
      %nat_add_zero(q) : {1n+Nat.add(q, 0n) == 1n+_ : Nat}
      {==}

def nat_add_assoc(x: Nat, +y: Nat, +z: Nat) -> {Nat.add(x, Nat.add(y, z)) == Nat.add(Nat.add(x, y), z) : Nat}:
  match x:
    case 0n:
      {==}
    case 1n+p:
      +q = p
      %nat_add_assoc(q, y, z) : {1n+Nat.add(q, Nat.add(y, z)) == 1n+_ : Nat}
      {==}

def nat_add_succ_r(y: Nat, +p: Nat) -> {Nat.add(y, 1n+p) == 1n+Nat.add(y, p) : Nat}:
  match y:
    case 0n:
      {==}
    case 1n+q0:
      +q = q0
      ih = nat_add_succ_r(q, p)
      sih = Equal.sym(Nat, Nat.add(q, 1n+p), 1n+Nat.add(q, p), ih)
      %sih : {1n+_ == 2n+Nat.add(q, p) : Nat}
      {==}

def nat_add_comm(x: Nat, +y: Nat) -> {Nat.add(x, y) == Nat.add(y, x) : Nat}:
  match x:
    case 0n:
      Equal.sym(Nat, Nat.add(y, 0n), y, nat_add_zero(y))
    case 1n+p0:
      +p = p0
      ih = nat_add_comm(p, y)
      succ = nat_add_succ_r(y, p)
      ssucc = Equal.sym(Nat, Nat.add(y, 1n+p), 1n+Nat.add(y, p), succ)
      %ssucc : {1n+Nat.add(p, y) == _ : Nat}
      sih = Equal.sym(Nat, Nat.add(p, y), Nat.add(y, p), ih)
      %sih : {1n+_ == 1n+Nat.add(y, p) : Nat}
      {==}

def add_by(c: Nat) -> (Nat -> Nat):
  x => Nat.add(x, c)

def nat_add_swap(+x: Nat, +y: Nat, +z: Nat) -> {Nat.add(x, Nat.add(y, z)) == Nat.add(y, Nat.add(x, z)) : Nat}:
  left = nat_add_assoc(x, y, z)
  comm = nat_add_comm(x, y)
  mid = Equal.cong(Nat, Nat, add_by(z), Nat.add(x, y), Nat.add(y, x), comm)
  right = Equal.sym(Nat, Nat.add(y, Nat.add(x, z)), Nat.add(Nat.add(y, x), z), nat_add_assoc(y, x, z))
  step = Equal.trans(Nat, Nat.add(Nat.add(x, y), z), Nat.add(Nat.add(y, x), z), Nat.add(y, Nat.add(x, z)), mid, right)
  Equal.trans(Nat, Nat.add(x, Nat.add(y, z)), Nat.add(Nat.add(x, y), z), Nat.add(y, Nat.add(x, z)), left, step)

def nat_mul_zero_r(k: Nat) -> {Nat.mul(k, 0n) == 0n : Nat}:
  match k:
    case 0n:
      {==}
    case 1n+p:
      nat_mul_zero_r(p)

def nat_mul_one_r(k: Nat) -> {Nat.mul(k, 1n) == k : Nat}:
  match k:
    case 0n:
      {==}
    case 1n+p:
      +q = p
      %nat_mul_one_r(q) : {Nat.add(1n, Nat.mul(q, 1n)) == Nat.add(1n, _) : Nat}
      {==}

def nat_mul_dist(x: Nat, +y: Nat, +z: Nat) -> {Nat.mul(Nat.add(x, y), z) == Nat.add(Nat.mul(x, z), Nat.mul(y, z)) : Nat}:
  match x:
    case 0n:
      {==}
    case 1n+p:
      +q = p
      ih = nat_mul_dist(q, y, z)
      sih = Equal.sym(Nat, Nat.mul(Nat.add(q, y), z), Nat.add(Nat.mul(q, z), Nat.mul(y, z)), ih)
      %sih : {Nat.add(z, _) == Nat.add(Nat.add(z, Nat.mul(q, z)), Nat.mul(y, z)) : Nat}
      nat_add_assoc(z, Nat.mul(q, z), Nat.mul(y, z))

def nat_mul_assoc(a: Nat, +b: Nat, +c: Nat) -> {Nat.mul(a, Nat.mul(b, c)) == Nat.mul(Nat.mul(a, b), c) : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      +q = p
      ih = nat_mul_assoc(q, b, c)
      dist = nat_mul_dist(b, Nat.mul(q, b), c)
      sdist = Equal.sym(Nat, Nat.mul(Nat.add(b, Nat.mul(q, b)), c), Nat.add(Nat.mul(b, c), Nat.mul(Nat.mul(q, b), c)), dist)
      %sdist : {Nat.add(Nat.mul(b, c), Nat.mul(q, Nat.mul(b, c))) == _ : Nat}
      sih = Equal.sym(Nat, Nat.mul(q, Nat.mul(b, c)), Nat.mul(Nat.mul(q, b), c), ih)
      %sih : {Nat.add(Nat.mul(b, c), _) == Nat.add(Nat.mul(b, c), Nat.mul(Nat.mul(q, b), c)) : Nat}
      {==}

def nat_mul_succ_r(b: Nat, +p: Nat) -> {Nat.mul(b, 1n+p) == Nat.add(b, Nat.mul(b, p)) : Nat}:
  match b:
    case 0n:
      {==}
    case 1n+q0:
      +q = q0
      ih = nat_mul_succ_r(q, p)
      sih = Equal.sym(Nat, Nat.mul(q, 1n+p), Nat.add(q, Nat.mul(q, p)), ih)
      %sih : {Nat.add(1n+p, _) == Nat.add(1n+q, Nat.add(p, Nat.mul(q, p))) : Nat}
      swap = nat_add_swap(p, q, Nat.mul(q, p))
      sswap = Equal.sym(Nat, Nat.add(p, Nat.add(q, Nat.mul(q, p))), Nat.add(q, Nat.add(p, Nat.mul(q, p))), swap)
      %sswap : {1n+_ == 1n+Nat.add(q, Nat.add(p, Nat.mul(q, p))) : Nat}
      {==}

def mul_by(c: Nat) -> (Nat -> Nat):
  x => Nat.mul(x, c)

def nat_mul_comm(a: Nat, +b: Nat) -> {Nat.mul(a, b) == Nat.mul(b, a) : Nat}:
  match a:
    case 0n:
      Equal.sym(Nat, Nat.mul(b, 0n), 0n, nat_mul_zero_r(b))
    case 1n+p0:
      +p = p0
      ih = nat_mul_comm(p, b)
      succ = nat_mul_succ_r(b, p)
      ssucc = Equal.sym(Nat, Nat.mul(b, 1n+p), Nat.add(b, Nat.mul(b, p)), succ)
      %ssucc : {Nat.add(b, Nat.mul(p, b)) == _ : Nat}
      sih = Equal.sym(Nat, Nat.mul(p, b), Nat.mul(b, p), ih)
      %sih : {Nat.add(b, _) == Nat.add(b, Nat.mul(b, p)) : Nat}
      {==}

def nat_mul_swap(+a: Nat, +b: Nat, +c: Nat) -> {Nat.mul(a, Nat.mul(b, c)) == Nat.mul(b, Nat.mul(a, c)) : Nat}:
  left = nat_mul_assoc(a, b, c)
  comm = nat_mul_comm(a, b)
  mid = Equal.cong(Nat, Nat, mul_by(c), Nat.mul(a, b), Nat.mul(b, a), comm)
  right = Equal.sym(Nat, Nat.mul(b, Nat.mul(a, c)), Nat.mul(Nat.mul(b, a), c), nat_mul_assoc(b, a, c))
  step = Equal.trans(Nat, Nat.mul(Nat.mul(a, b), c), Nat.mul(Nat.mul(b, a), c), Nat.mul(b, Nat.mul(a, c)), mid, right)
  Equal.trans(Nat, Nat.mul(a, Nat.mul(b, c)), Nat.mul(Nat.mul(a, b), c), Nat.mul(b, Nat.mul(a, c)), left, step)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("lemmas-ok")
