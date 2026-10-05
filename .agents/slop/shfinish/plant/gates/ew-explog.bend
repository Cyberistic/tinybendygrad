import Base
import ./../tinybendygrad/mixin/elementwise.bend as E

# The GATE DRIVER for `log`, `log10` and `exp`. It calls elementwise's OWN row functions,
# so the gate measures what `main` runs rather than a second implementation of it.
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- E.t_log()
    b : Unit <- E.t_log10()
    E.t_exp()
