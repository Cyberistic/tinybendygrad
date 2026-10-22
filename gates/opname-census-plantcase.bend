# gates/opname-census-plantcase.bend -- THE FIXTURE for `gates/opname-census-gate.py --plant`.
#
# IT EXISTS SO THE PLANT HAS A SUBJECT IT OWNS.  The plant's job is to put an op the port's
# `Op` enum does not declare back into a driver and to prove the census goes red on it.  A
# subject another unit owns is a SHARED PATH, and `AGENTS.md` records what happens to shared
# paths: a file that others are executing is a path others hold, and the safe form is to
# write a NEW path and leave the old one alone.  So the subject is THIS file, and the plant
# edits a COPY of it under a scratch name, and the copy is deleted the moment the run ends.
#
# TWO SHAPES, AND THE PLANT NEEDS BOTH.
#
#   plant_op    ONE statement on its own line.  The control appends a comment to a line that
#               carries ONE statement, so the comment cannot swallow anything.
#   plant_pair  a LIST OPENER and its first element on ONE line (`  [  O.OpsADD{},`), so the
#               control's WRONG SHAPE -- a comment BETWEEN the two parts -- has a line to
#               happen on.  A `#` runs to the end of the line in bend, so a comment inserted
#               between the opener and the element DELETES the element, and the file still
#               COMPILES.  Only a comment-stripped proof catches that, and the proof is
#               what this file's second def is for.
#
# EVERY EDIT IS A TEXT EDIT ON THE WORKING TREE.  NEVER `git show HEAD:` -- a plant that
# reads HEAD plants nothing the moment HEAD carries the fix.
import Base
import ./../tinybendygrad/uop/ops.bend as O

# THE ANCHOR.  `O.OpsADD{}` is a DECLARED member, so this file is not a finding; the plant
# replaces it with a name the enum does not declare, and the census must go red on the
# result.  The replacement is the EXACT text that was in the tree before upstream's
# `4e0192eaf remove Ops.GROUP (#18637)`, because the question the plant asks is "does the
# compiler refuse a name the enum does not declare", and a made-up op would answer a
# different question.
def plant_op() -> O.Op:
  O.OpsADD{}

# THE TWO-PART LINE.  The opener and its first element share one line, so a comment
# inserted between them deletes the element and leaves the file compiling -- the shape that
# a compiler's verdict cannot catch and a comment-stripped proof can.
def plant_pair() -> List<&2, O.Op>:
  [  O.OpsADD{},
    O.OpsADD{}]

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("opname-census-plantcase")
