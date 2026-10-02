p = "tinybendygrad/runtime/support/autogen.bend"
s = open(p).read()
old_start = s.index("# autogen.py:113 the suggested name")
old_end = s.index("# ===========================================================================\n# SECTION 13 --")
new = '''# autogen.py:113 the suggested name for an ELABORATED type, and :128/:142 the
# `::`-to-`_` and space-to-`_` rewrites that make a C++ name a Python
# identifier. BOTH are `str.replace`, and `String.replace` DOES NOT EXIST in
# bend 2.0.34 -- `references/bend/bend2/base.bend` has no such def and no
# intrinsic backs it, so this is WALL 2's second mouth.
#
# The walk is fixed-stride, which is what makes it expressible at all. A
# general substring replace needs "either consume 1 or consume len(pattern)",
# i.e. TWO recursive calls in one arm, and bend refuses two self-calls in an
# arm (`references/bend` rejects the second with "a decreasing self-call"). A
# FIXED pattern length turns it into one stride: take exactly 2 chars, decide,
# recurse once on the tail. The accumulator goes SECOND because bend's descent
# rule wants the shrinking argument first.
def colon() -> Char: ':'

def rep_emit2(c1: Char, c2: Char) -> List<&2, Char>:
  Bool.pick(List<&2, Char>, Bool.and(Char.is_eq(c1, colon()), Char.is_eq(c2, colon())), ["_"], [c1, c2])

def rep_go2(cs: List<&2, Char>, acc: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}: List.reverse(acc)
    case c1 c2 rest: rep_go2(rest, List.append(&2, Char, acc, rep_emit2(c1, c2)))

def rep_emit1(c1: Char) -> List<&2, Char>:
  Bool.pick(List<&2, Char>, Char.is_eq(c1, space()), ["_"], [c1])

def rep_go1(cs: List<&2, Char>, acc: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}: List.reverse(acc)
    case c1 rest: rep_go1(rest, List.append(&2, Char, acc, rep_emit1(c1)))

def space() -> Char: ' '

def colons_to_underscores(n: String) -> String:
  String.from_list(rep_go2(String.to_list(n), Nil{}))

def spaces_to_underscores(n: String) -> String:
  String.from_list(rep_go1(String.to_list(n), Nil{}))

# autogen.py:142 `real_nm.replace(' ', '_').replace('::', '_')` -- the SPACE
# rewrite runs FIRST and the `::` rewrite second, and on a C++ name that order
# is observable, so `rep_go1` then `rep_go2`, not the other way round.
def record_nm(n: String) -> String: colons_to_underscores(spaces_to_underscores(n))

'''
s = s[:old_start] + new + s[old_end:]
open(p, "w").write(s)
print("ok")
