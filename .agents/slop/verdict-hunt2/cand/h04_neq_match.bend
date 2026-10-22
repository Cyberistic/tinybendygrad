import Base

def bad(a: Nat, b: Nat) -> Empty:
  match {a != b : Nat}:
    case e:
      match e:
