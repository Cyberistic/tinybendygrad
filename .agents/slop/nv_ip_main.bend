# ===========================================================================
# main. FOUR gate sections and a sentinel, in the order they are declared.
# `ip-done=1` is a bare term at the end because a `do IO<Unit>` block may end
# with one only, and it is the row the differ reads as "the suite ran to the
# end" -- a suite that dies half way prints no sentinel and every later section
# reads as MISSING rather than as WRONG.
# ===========================================================================

def main() -> IO(Unit):
  do IO<Unit>:
    +a : Unit <- t_tables()
    +b : Unit <- t_arith()
    +c : Unit <- t_trace()
    +d : Unit <- t_refuse()
    IO.print("ip-done=1")