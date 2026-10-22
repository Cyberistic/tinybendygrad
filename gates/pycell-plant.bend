# gates/pycell-plant.bend -- THE FIXTURE for the census's own self-check.
#
# FOUR CELLS, FOUR SHAPES, AND THE VERDICT EACH ONE MUST CARRY:
#
#   plant literal     the `py=` slot holds a LITERAL                 -> TRANSCRIPTION
#   plant param       the `py=` slot is a PARAMETER and the CALLER
#                     fills it with a LITERAL                       -> TRANSCRIPTION
#   plant derived     the `py=` slot holds the PORT's own call      -> DERIVED
#   plant number      the `py=` slot holds a NUMBER                 -> TRANSCRIPTION
#
# WHY A FIXTURE AND NOT A COPY OF THE EXPECTATIONS: a fixture retyped by hand agrees with
# the instrument by construction, so the PLANT edits THIS TEXT and asserts that the
# verdict MOVES.  `gates/pycell-plant.py` is the only thing that edits it, and every arm
# is a TEXT EDIT -- **never `git show HEAD:`**, because a plant that reads HEAD plants
# nothing the moment HEAD carries the fix.
def r(+nm: String, +got: String, +want: String) -> String:
  String.concat([nm, " = [", got, "]   py=[", want, "]"])

def port_answer(x: U32) -> U32: U32.add(x, 1)

def row_from_param(nm: String, got: String, lit: String) -> String:
  r(nm, got, lit)

def main() -> String:
  do String:
  String.concat([
    r("plant literal", U32.show(port_answer(1)), "2"),
    row_from_param("plant param", U32.show(port_answer(2)), "3"),
    r("plant derived", U32.show(port_answer(3)), U32.show(port_answer(4))),
    r("plant number", U32.show(port_answer(5)), 6),
  ])
