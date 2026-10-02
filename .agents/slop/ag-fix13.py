p = "tinybendygrad/runtime/support/autogen.bend"
s = open(p).read()
reps = [
 # BUG 1: the accumulator is already in order; reversing it reversed the answer.
 ("    case Nil{}: List.reverse(&2, Char, rep_flush2(acc))", "    case Nil{}: rep_flush2(acc)"),
 ("    case Nil{}: List.reverse(&2, Char, acc)\n    case c1 <> rest: rep_go1(rest,",
  "    case Nil{}: acc\n    case c1 <> rest: rep_go1(rest,"),
 # BUG 2: `{paths}` is the SOURCE TEXT of gen's `paths=` argument (autogen.py:276
 # interpolates it, it does not join it), so it is a String and there is no comma
 # unless it is non-empty.
 ("""def emit_dll_line(nm: String, dll: String, +paths: List<&2, String>, errno: Bool) -> String:
  String.concat(["dll = c.DLL('", nm, "', ", dll, ", ", String.join(paths, ", "), Bool.pick(String, errno, ", use_errno=True", ""), ")"])""",
  """def emit_dll_line(nm: String, dll: String, paths: String, errno: Bool) -> String:
  String.concat(["dll = c.DLL('", nm, "', ", dll,
                 Bool.pick(String, String.is_empty(paths), "", String.concat([", ", paths])),
                 Bool.pick(String, errno, ", use_errno=True", ""), ")"])"""),
 ('IO.print("emit.dll " ++ emit_dll_line("agtest", "\'c\'", Nil{}, False{}))',
  'IO.print("emit.dll " ++ emit_dll_line("agtest", "\'c\'", "", False{}))'),
 ('IO.print("emit.dllerr " ++ emit_dll_line("libc", "\'c\'", ["\'/usr/lib/x86_64-linux-gnu\'"], True{}))',
  'IO.print("emit.dllerr " ++ emit_dll_line("libc", "\'c\'", "[\'/usr/lib/x86_64-linux-gnu\']", True{}))'),
 # BUG 3: that row hand-wrote `POINTER[...]` where the generator emits
 # `c.POINTER[...]`, so it restated the code instead of testing it.
 ('IO.print("emit.indll " ++ emit_in_dll("stdin", "POINTER[struct__IO_FILE]", "\'c\'"))',
  'IO.print("emit.indll " ++ emit_in_dll("stdin", emit_pointer("struct__IO_FILE"), "\'c\'"))'),
]
for a, b in reps:
    assert a in s, a[:70]
    s = s.replace(a, b)

# BUG 4, and the important one. Python's dict LITERAL keeps the LAST key, so
# `CXType_Char_S:"bytes"` overwrites the "int" that `ints` contributed. `th_at`
# found the FIRST match and answered "int". Fix: last match wins, which is what
# a dict literal does -- and the table keeps the duplicate so the overwrite stays
# VISIBLE in the source instead of being quietly pre-resolved.
old = """def th_at(+k: U32, xs: List<&2, TH>) -> Maybe<&2, TH>:
  match xs:
    case Nil{}: None{}
    case TH{+kind, hint} <> rest: List.find.put(TH, TH{kind, hint}, th_at(k, rest), U32.is_eq(kind, k))"""
new = """# LAST MATCH WINS, and that is the whole point of this def being different
# from `te_at`. autogen.py:108-109 builds a dict LITERAL, and a later key
# overwrites an earlier one: `Char_S`(13) is in `ints`, so it arrives as "int",
# and the explicit `CXType_Char_S:"bytes"` overwrites it. A first-match lookup
# answers "int" and every `char*` in every generated binding comes out with the
# wrong ctypes type -- which is precisely the silent-constant class this project
# has already been burned by. `hint.chars` is the row that saw it.
def th_last(+k: U32, xs: List<&2, TH>) -> Maybe<&2, TH>:
  match xs:
    case Nil{}: None{}
    case TH{+kind, hint} <> rest:
      Bool.pick(Maybe<&2, TH>, th_hit(k, xs), Some{ TH{kind, hint} }, th_last(k, rest))

def th_at(+k: U32, xs: List<&2, TH>) -> Maybe<&2, TH>: th_last(k, xs)"""
assert old in s
s = s.replace(old, new)
open(p, "w").write(s)
print("ok")
