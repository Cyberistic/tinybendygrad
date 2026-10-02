import io
P = "tinybendygrad/runtime/support/usb.bend"
s = io.open(P).read()

# 1. enum_nm must be LAST-wins, like the dict. It was first-wins, which the
#    differ caught on `usb_classcode_6_name` (bend said IMAGE, CPython said PTP).
a = s.index("# value -> name. LAST match wins")
b = s.index("# name -> value, LAST match wins")
NEW_NM = '''# value -> name, LAST match wins: `enum_libusb_class_code` gives 6 TWO names and
# the generated dict keeps the LAST, so a first-wins fold is wrong and the differ
# says so on `usb_classcode_6_name`.
def enum_nm.go(n: Nat, +v: U32, es: List<&2, Ent>, hit: String) -> String:
  match n:
    case 0n: hit
    case 1n+m:
      match es:
        case Nil{}: hit
        case Ent{vv, nn} <> t: enum_nm.go(m, v, t, Bool.pick(String, U32.is_eq(vv, v), nn, hit))

def enum_nm(+v: U32, +es: List<&2, Ent>) -> String:
  enum_nm.go(List.length(&2, Ent, es), v, es, "LIBUSB_ENUM_NONE")

'''
s = s[:a] + NEW_NM + s[b:]

# 2. the walk. The SEEN-SET version was reading a `+` slot AFTER handing it to
#    `List.contains`, which MOVES it -- so `nn <> sn` consed a moved value and
#    every seen set already contained everything, which is why ZERO `_n_` rows
#    were emitted. The fix is to walk ONE list and fold over ANOTHER, so the
#    folded list is never matched and so never consumed.
a = s.index("# ONE entry, BOTH rows, over ONE pass.")
b = s.index("def t_consts()")
NEW_WALK = '''# ONE entry, BOTH rows, from ONE walk.
#
# TWO LISTS, ON PURPOSE. `enum_rows.go` MATCHES `r` (the walk) and folds over
# `es` (the whole table), so `es` is never matched and so is never consumed --
# the version that matched the table and kept SEEN SETS instead handed each `+`
# slot to `List.contains`, which MOVES it, and the cons after it built an empty
# list. That is the whole bug the differ found: zero `_n_` rows, every seen set
# already full.
#
# `r` is the REVERSED table so the rows come out in the header's own order.
def enum_both(+tag: String, +nm: String, +v: U32, +es: List<&2, Ent>,
              t: List<&2, Ent>, +acc: List<&2, String>) -> List<&2, String>:
  i1(String.concat(["usb_", tag, "_v_", nm]), enum_val(nm, es))
    <> (s1(String.concat(["usb_", tag, "_n_", nm]), enum_nm(v, es)) <> enum_rows.go(tag, es, t, acc))

def enum_rows.go(+tag: String, +es: List<&2, Ent>, r: List<&2, Ent>,
                 +acc: List<&2, String>) -> List<&2, String>:
  match r:
    case Nil{}: acc
    case Ent{v, nm} <> t: enum_both(tag, nm, v, es, t, acc)

def enum_rows(tag: String, es: List<&2, Ent>) -> List<&2, String>:
  enum_rows.go(tag, es, List.reverse(&2, Ent, es), Nil{})

'''
s = s[:a] + NEW_WALK + s[b:]
io.open(P, "w").write(s)
print("ok")