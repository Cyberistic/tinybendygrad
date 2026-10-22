type Emp is Data:
type Bit is Data:
  B0{}
  B1{}
type W is Data:
  W{b: Bit, x: Emp}

law uses:
  for a: W
  Bit

def uses(a):
  B0{}
