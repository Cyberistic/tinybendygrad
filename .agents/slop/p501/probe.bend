import ./../../tinybendygrad/LAWS/spec.bend as S

def is_mov(m: Bool) -> Bool: m

# SHAPE A: self-call inside Bool.pick
def base(fuel: Nat, ar: U32, self: U32) -> U32:
  match fuel:
    case 0n: self
    case 1n+p: Bool.pick(U32, is_mov(True{}), base(p, ar, U32.add(self, 1)), self)

def main() -> IO(Unit):
  IO.print(U32.show(base(4n, 0, 7)))
