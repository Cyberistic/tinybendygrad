import io

P = "tinybendygrad/runtime/support/usb.bend"
s = io.open(P).read()

MISSING = '''# name -> value, LAST match wins for the same reason. A NAME no entry has is
# `NOT_FOUND` and never 0: 0 is LIBUSB_SUCCESS's and LIBUSB_REQUEST_TYPE_STANDARD's
# and LIBUSB_TRANSFER_COMPLETED's value, so a silent 0 would be indistinguishable
# from a real constant. 4294967295 is LIBUSB_ERROR_IO's bit pattern, and
# `usb_enumval_absent_not_found` is the row that says which one it is.
def enum_val.go(n: Nat, +nm: String, es: List<&2, Ent>, hit: U32) -> U32:
  match n:
    case 0n: hit
    case 1n+m:
      match es:
        case Nil{}: hit
        case Ent{vv, nn} <> t: enum_val.go(m, nm, t, Bool.pick(U32, String.eq(nn, nm), vv, hit))

# PORT-INTERNAL, and the only constant in this file with no line in `usb.py`. It
# is 0xFFFFFFFF so that it cannot be confused with a real `enum_libusb_*` value:
# the negative error codes are the only ones in that range and the largest is -1,
# which is LIBUSB_ERROR_IO. `usb_enumval_absent_not_found` is the row.
def NOT_FOUND() -> U32: 4294967295

def enum_val(+nm: String, +es: List<&2, Ent>) -> U32:
  enum_val.go(List.length(&2, Ent, es), nm, es, NOT_FOUND())

# ONE entry, BOTH rows, from ONE walk.
#
# TWO LISTS, ON PURPOSE. `enum_rows.go` MATCHES `r` (the walk) and folds over `es`
# (the whole table), so `es` is never matched and so is never consumed -- the
# version that matched the table and kept SEEN SETS instead handed each `+` slot to
# `List.contains`, which MOVES it, and the cons after it built an empty list. That
# is the whole bug the differ found: zero `_n_` rows and every seen set already
# full. `r` is the REVERSED table so the rows come out in the header's own order.
def enum_rows.go(+tag: String, +es: List<&2, Ent>, r: List<&2, Ent>,
                 +acc: List<&2, String>) -> List<&2, String>:
  match r:
    case Nil{}: acc
    case Ent{v, nm} <> t:
      +vv = v
      +nn = nm
      i1(String.concat(["usb_", tag, "_v_", nn]), enum_val(nn, es))
        <> (s1(String.concat(["usb_", tag, "_n_", nn]), enum_nm(vv, es)) <> enum_rows.go(tag, es, t, acc))

def enum_rows(tag: String, es: List<&2, Ent>) -> List<&2, String>:
  enum_rows.go(tag, es, List.reverse(&2, Ent, es), Nil{})

'''

# the accident left the doc comment in place and cut the defs; splice them back
old = '''# name -> value, LAST match wins for the same reason. A NAME no entry has is
# `NOT_FOUND` and never 0: 0 is LIBUSB_SUCCESS's and LIBUSB_REQUEST_TYPE_STANDARD's
# and LIBUSB_TRANSFER_COMPLETED's value, so a silent 0 would be indistinguishable
# from a real constant. 4294967295 is LIBUSB_ERROR_IO's bit pattern, and
# `usb_enumval_absent_not_found` is the row that says which one it is.
'''
assert old in s
s = s.replace(old, MISSING, 1)

# and the mutation table belongs at the END, before the entry point
i = s.index("# ===========================================================================\n# THE MUTATION TABLE.")
j = s.index("# ===========================================================================\n# THE FFI SEAM SPLIT.")
assert i < j
mut = s[i:j]
s = s[:i] + s[j:]
anchor = "# ===========================================================================\n# THE ENTRY POINT."
s = s.replace(anchor, mut + anchor, 1)
io.open(P, "w").write(s)
print("spliced")