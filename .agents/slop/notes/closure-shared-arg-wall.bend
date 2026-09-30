import Base

type V is Data:
  VTrue{}

type A is Data:
  A{n: U32}

# a rule whose body needs the arena TWICE
def needs_twice(+ar: A, i: U32) -> V:
  VTrue{}

type R1 is Type:
  Ok{test: (A -> U32 -> V)}

def needs_once(ar: A, i: U32) -> V:
  VTrue{}

def r_ok() -> R1:
  Ok{needs_once}

type R2 is Type:
  Shared{test: (A -> U32 -> V)}

def r_shared() -> R2:
  Shared{needs_twice}

def main() -> U32:
  0
