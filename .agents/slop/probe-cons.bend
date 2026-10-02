import Base
import ./../../tinybendygrad/uop/ops.bend as O

def oo(+xs: List<&2, O.Op>) -> String:
  match xs:
    case Nil{}   : ""
    case h <> +t : String.concat([O.Ops.name.of(h), ",", oo(t)])

def uu(+xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}   : ""
    case h <> +t : String.concat([U32.show(h), ",", uu(t)])

# input given in REVERSE of the wanted answer, so prepend -> wanted, append -> given
def co(+drop: Bool, +ops: List<&2, O.Op>) -> List<&2, O.Op>:
  match ops:
    case Nil{}   : Nil{}
    case o <> +t : Bool.pick(List<&2, O.Op>, drop, co(drop, t), o <> co(drop, t))

def cu(+drop: Bool, +ops: List<&2, U32>) -> List<&2, U32>:
  match ops:
    case Nil{}   : Nil{}
    case o <> +t : Bool.pick(List<&2, U32>, drop, cu(drop, t), o <> cu(drop, t))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["op_keep=", oo(co(False{}, [O.OpsXOR{}, O.OpsMUL{}, O.OpsADD{}])),
      " u32_keep=", uu(cu(False{}, [3, 2, 1]))]))
