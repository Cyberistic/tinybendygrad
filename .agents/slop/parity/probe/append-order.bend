# PROBE: DOES BEND's `List.append` PUT ITS **FIRST** LIST ARGUMENT **FIRST** IN THE RESULT?
#
# ⇒⇒⇒ THE MEASUREMENT THIS PROBE EXISTS FOR: `cstyle.bend`'s `st_kernel` SPELLS
# `List.append(&2, String, [x], St.kernel(st))` -- **THE NEW ELEMENT FIRST** -- AND `base.bend`'s OWN
# `List.append(xs, ys)` PUTS `xs` FIRST, SO THAT SPELLING IS A **PREPEND, O(1)**. ⇒⇒⇒ BUT THE
# COMPILED FORM OF A **PRE-FIX** BUILD READ `$$List_append(St_kernel(_st_0), {head: _x_0})` -- **THE
# NEW ELEMENT SECOND** -- WHICH IS AN **APPEND AT THE END, O(n)**, AND `base.bend`'s `List.append` IS
# **O(|xs|)**. ⇒⇒⇒ ⇒⇒⇒ SO THE QUESTION IS NOT ACADEMIC: **THE ARGUMENT ORDER DECIDES WHETHER THE
# RENDER IS O(n) OR O(n²)**, AND THE COMPILED FORM IS WHAT RUNS.
#
# ⇒⇒⇒ ⇒⇒⇒ **AND A PROBE THAT CANNOT GO RED IS NOT A PROBE.** ⇒⇒⇒ ⇒⇒⇒ SO THIS ONE **FAILS** WHEN
# THE ORDER IS NOT WHAT `base.bend` PROMISES, AND THE PLANT IS **THE ORDER ITSELF REVERSED** -- so
# THE FAILURE PATH IS EXERCISED BY THE SAME MECHANISM THAT EXERCISES THE SUCCESS PATH.
#
# ⇒⇒⇒ ⇒⇒⇒ AND THE ANSWER, MEASURED: **THE COMPILER DOES **NOT** REORDER.** `append([a],[b,c])` IS
# `a|b|c` AND `append([b,c],[a])` IS `b|c|a`, AND THE PROBE's OWN COMPILED FORM SHOWS IT
# (`$$List_append(["a"], ["b","c"])`).

import Base

def show(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case Con{head, tail}: String.concat([head, "|", show(tail)])

# **THE TWO CALLS, AS STRINGS.** ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ A `do`-BLOCK LET IS A **LINEAR** VALUE AND "CONSUMED
# MORE THAN ONCE" IS A COMPILE ERROR, ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ SO EVERY VALUE IS CONSUMED EXACTLY ONCE AND THE
# PROBE's FIVE READS ARE FIVE SEPARATE BINDINGS.
def order_a() -> String: show(List.append(&2, String, ["a"], ["b", "c"]))
def order_b() -> String: show(List.append(&2, String, ["b", "c"], ["a"]))

# **THE PLANT: THE SAME CALL WITH ITS LISTS SWAPPED.** ⇒⇒⇒ IT MUST **FAIL**, AND IT FAILS FOR THE
# SAME REASON THE REAL ONE PASSES -- THE ORDER IS THE ORDER.
def plant() -> Bool: String.eq(order_b(), "a|b|c|")

# **THE ASSERTION, AS A `def` SO IT CAN HEAD A `match`.** ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ A `match` IN BEND HEADS A
# `def` BODY AND IS NOT A TERM, AND **IT CANNOT SCRUTINIZE A COMPUTED VALUE** -- "give it its own
# def" -- ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ AND THE SCRUTINEE MUST BE A **BARE PARAMETER**, NOT A CALL. ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ SO
# THE COMBINATION IS COMPUTED **BY THE CALLER** AND PASSED IN. ⇒⇒⇒ THIS IS THE TREE's HOUSE STYLE
# (`cstyle.bend`'s OWN `.go` SHAPE).
def verdict(wrong: Bool) -> IO(Unit):
  match wrong:
    case True{}: IO.die(Unit, 1, "append-order-probe: List.append did not put its first argument first")
    case False{}: IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    # **⇒⇒⇒ AND THE TWO PRINTS AND THE TWO ASSERTIONS ARE **FOUR** READS OF **TWO** CALLS, SO THE
    # CALLS ARE MADE TWICE -- ONCE FOR THE PRINT AND ONCE FOR THE ASSERTION. ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ THAT IS
    # FINE, BECAUSE A `def` CALL IS NOT A LINEAR VALUE: IT IS A FUNCTION, AND FUNCTIONS ARE NOT
    # CONSUMED.**
    IO.print(String.concat(["append([a],[b,c]) = ", order_a(), "\n"]))
    IO.print(String.concat(["append([b,c],[a]) = ", order_b(), "\n"]))
    # **THE ASSERTION: `append(xs, ys)` PUTS `xs` FIRST.**
    ok : Bool = String.eq(order_a(), "a|b|c|")
    # **AND THE PLANT MUST NOT HOLD.**
    pl : Bool = plant()
    wrong : Bool = Bool.or(Bool.not(ok), pl)
    IO.bind(Unit, Unit, verdict(wrong), _ => IO.pure(Unit, Unit{}))
