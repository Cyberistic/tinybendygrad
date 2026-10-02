import Base

def show(+xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}   : ""
    case h <> +t : String.concat([U32.show(h), ",", show(t)])

# A: single self-call, append at END, self-call in the ARGUMENT
def fa(+xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}   : Nil{}
    case c <> +t : List.append(&2, U32, fa(t), [c])

# E: same, but the self-call is BOUND TO A LOCAL first
def fe(+xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}   : Nil{}
    case c <> +t :
      ys = fe(t)
      List.append(&2, U32, ys, [c])

# B: cons
def fb(+xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}   : Nil{}
    case c <> +t : c <> fb(t)

# G: cons with the self-call bound to a local
def fg(+xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}   : Nil{}
    case c <> +t :
      ys = fb(t)
      c <> ys

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["fa=", show(fa([2, 1, 6])), " fb=", show(fb([2, 1, 6])),
      " fe=", show(fe([2, 1, 6])), " fg=", show(fg([2, 1, 6]))]))
