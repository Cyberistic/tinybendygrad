import Base
import ../LAWS/spec.bend as S

def myfoo(d: S.Dt) -> U32:
  S.Dt.itemsize(d)

def main() -> U32:
  myfoo(S.uint8())
