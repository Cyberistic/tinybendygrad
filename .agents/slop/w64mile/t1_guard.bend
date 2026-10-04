# Does the `#ifdef CID(...)` guard in runtime/dtype.c survive when NO seam is
# called? W64-MILE build fact 1 says the guard is false for every binding.
import ../../../tinybendygrad/dtype.bend as D
import ../../../tinybendygrad/helpers.bend as H

def main() -> IO(Nat):
  do IO<Nat>:
    IO.print("no seam called")
    return 0n
