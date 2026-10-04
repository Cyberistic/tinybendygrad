# WALL-4 REPRO (reproduced independently -- the artifact cited by
# autogen.bend:459 as `.agents/slop/agprobe/p20.bend` did NOT exist on disk).
#
# CLAIM under test (autogen.bend:453-459): `tname`'s RECORD arm needs TWO
# descents in one arm --
#   (a) autogen.py:147 resolves `tname` for EACH field, a descent on the
#       field's TYPE, and
#   (b) autogen.py:147-153 then continues with the REMAINING fields, a
#       descent on the field LIST,
# and bend refuses the second, reporting "a decreasing self-call (arguments are
# read left to right: each passed unchanged until one shrinks)".
#
# The parameter order matches `rows_br_go` / `gtn_find` in autogen.bend: the
# LIST is FIRST, so the shrinking argument is read first.
#
#   walk_a  ONE descent, list shrinks                     -> MUST compile
#   walk_b  TWO descents: the type descent passes the list
#           UNCHANGED, so it has no shrinking argument     -> the claim
#
# The claim is supported only if walk_a compiles and walk_b is refused.

import Base

type Fld is Data: Fld{nm: String, ty: Ty}
type Ty  is Data: Ty{kind: U32, flds: List<&2, Fld>}

# (A) ONE descent.  The list shrinks.  MUST compile.
def walk_a(xs: List<&2, Fld>, g: Ty) -> List<&2, Fld>:
  match xs:
    case Nil{}: Nil{}
    case Fld{+nm, ty} <> rest: walk_a(rest, ty)


def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("A ok")
