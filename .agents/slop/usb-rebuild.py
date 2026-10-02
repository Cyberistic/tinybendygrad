import io

P = "tinybendygrad/runtime/support/usb.bend"
s = io.open(P).read()
HERE = ".agents/slop/"

trace = io.open(HERE + "usb-secure.bend.txt").read()
strings = io.open(HERE + "usb-sblock.bend.txt").read()

# The trace rows, with the refusal ordinals and the inventory.
rows = '''# ===========================================================================
# THE TRACE ROWS. Three things are gateable about a trace and only three: the
# IDENTITY of each call, the ORDER of the calls, and the TRUNCATION POINT of a
# refusal. All three are whole-value rows.
# ===========================================================================

def t_trace() -> IO(Unit):
  IO.print(lines_of(
    # :23-26 `USB3.ctx()` -- the option is conditional on `DEBUG >= 6` and there
    # is no third call.
    [s1("usb_ctx_order_debug6", Tr.sym(usb_ctx(True{}, Tr.of()))),
     s1("usb_ctx_order_nodebug", Tr.sym(usb_ctx(False{}, Tr.of()))),
     u1("usb_ctx_n_debug6", Tr.n(usb_ctx(True{}, Tr.of()))),
     u1("usb_ctx_n_nodebug", Tr.n(usb_ctx(False{}, Tr.of()))),
     # :32-36 the enumeration, on ZERO, ONE and TWO devices, hit and miss.
     s1("usb_enum_order_0", Tr.sym(usb_enum(0, False{}, 0, 0, Tr.of()))),
     s1("usb_enum_order_1_miss", Tr.sym(usb_enum(1, False{}, 0, 0, Tr.of()))),
     s1("usb_enum_order_1_hit", Tr.sym(usb_enum(1, True{}, 3, 7, Tr.of()))),
     s1("usb_enum_order_2_hit", Tr.sym(usb_enum(2, True{}, 3, 7, Tr.of()))),
     u1("usb_enum_n_0", Tr.n(usb_enum(0, False{}, 0, 0, Tr.of()))),
     u1("usb_enum_n_1_miss", Tr.n(usb_enum(1, False{}, 0, 0, Tr.of()))),
     u1("usb_enum_n_1_hit", Tr.n(usb_enum(1, True{}, 3, 7, Tr.of()))),
     u1("usb_enum_n_2_hit", Tr.n(usb_enum(2, True{}, 3, 7, Tr.of()))),
     # :39-62 the open, on both kernel-driver branches.
     s1("usb_open_order_nodetach", Tr.sym(usb_open(True{}, False{}, Tr.of()))),
     s1("usb_open_order_detach", Tr.sym(usb_open(True{}, True{}, Tr.of()))),
     u1("usb_open_n_nodetach", Tr.n(usb_open(True{}, False{}, Tr.of()))),
     u1("usb_open_n_detach", Tr.n(usb_open(True{}, True{}, Tr.of()))),
     # `Tr.raise` SITES, straight from `usb.py`'s `checked` wrapper. These are the
     # rows that make a refusal ordinal mean something.
     b1("usb_ctx_init_checked", True{}),
     b1("usb_ctx_setoption_checked", True{}),
     b1("usb_enum_getdevlist_checked", True{}),
     b1("usb_enum_ref_device_checked", False{}),
     b1("usb_enum_free_checked", False{}),
     b1("usb_open_checked", True{}),
     b1("usb_open_getdevice_checked", False{}),
     b1("usb_open_strascii_checked", True{}),
     b1("usb_open_kdrv_checked", True{}),
     b1("usb_open_setcfg_checked", True{}),
     b1("usb_open_claim_checked", True{}),
     b1("usb_open_alt_checked", True{}),
     s1("usb_list_label_b3_a7", list_label(3, 7)),
     s1("usb_list_label_b0_a0", list_label(0, 0)),
     s1("usb_list_label_b255_a127", list_label(255, 127))]))

# THE SELECTION, with the NEGATIVE CASE one row from its positive. A descriptor
# whose idVendor matches and whose idProduct does not is NOT selected, and one
# whose product matches with the vendor swapped is NOT either -- the comparison is
# a PAIR and not two independent halves.
def t_select() -> IO(Unit):
  IO.print(lines_of(
    [b1("usb_list_match_exact", list_match(7531, 260, 7531, 260)),
     b1("usb_list_match_vendor_only", list_match(7531, 260, 7531, 261)),
     b1("usb_list_match_product_only", list_match(7531, 260, 1204, 260)),
     b1("usb_list_match_both_wrong", list_match(7531, 260, 1204, 305)),
     b1("usb_list_match_zero_zero", list_match(0, 0, 0, 0)),
     b1("usb_list_match_ffff_ffff", list_match(65535, 65535, 65535, 65535)),
     # the two descriptor field ORDINALS the comparison reads, by name
     u1("usb_list_ix_idvendor", Fld.find("idVendor", F_DEVICE_DESCRIPTOR())),
     u1("usb_list_ix_idproduct", Fld.find("idProduct", F_DEVICE_DESCRIPTOR()))]))

# THE REFUSALS. Each is a TRUNCATION and the row is the trace that survived, so
# the ordinal of the failing emit is IN the value: a refusal moved one step late
# is a different string, not a missing row.
#
# THE ORDINALS. `Tr.raise` records the failing call and THEN sets `refused`, so a
# refusal at `bad_at = 4` leaves a FOUR-call trace. The no-detach open emits
# 1 OPEN, 2 GET_DEVICE, 3 GET_DESC, 4 STR_ASCII, 5 SET_CONFIG, 6 CLAIM,
# 7 SET_ALT; the detach branch adds 5 KDRV_ACTIVE, 6 DETACH, 7 RESET and shifts
# the rest by three.
def t_refuse() -> IO(Unit):
  IO.print(lines_of(
    [s1("usb_open_refuse_1_open", Tr.sym(usb_open(True{}, False{}, Tr.fail_at(Tr.of(), 1)))),
     s1("usb_open_refuse_4_product", Tr.sym(usb_open(False{}, False{}, Tr.fail_at(Tr.of(), 4)))),
     s1("usb_open_refuse_5_config", Tr.sym(usb_open(True{}, False{}, Tr.fail_at(Tr.of(), 5)))),
     s1("usb_open_refuse_6_claim", Tr.sym(usb_open(True{}, False{}, Tr.fail_at(Tr.of(), 6)))),
     s1("usb_open_refuse_7_alt", Tr.sym(usb_open(True{}, False{}, Tr.fail_at(Tr.of(), 7)))),
     s1("usb_open_refuse_5_kdrv", Tr.sym(usb_open(True{}, True{}, Tr.fail_at(Tr.of(), 5)))),
     s1("usb_open_refuse_8_detach", Tr.sym(usb_open(True{}, True{}, Tr.fail_at(Tr.of(), 8)))),
     s1("usb_open_refuse_10_alt", Tr.sym(usb_open(True{}, True{}, Tr.fail_at(Tr.of(), 10)))),
     b1("usb_open_refused_4", Tr.refused(usb_open(False{}, False{}, Tr.fail_at(Tr.of(), 4)))),
     b1("usb_open_refused_6", Tr.refused(usb_open(True{}, False{}, Tr.fail_at(Tr.of(), 6)))),
     b1("usb_open_refused_beyond_10", Tr.refused(usb_open(True{}, True{}, Tr.fail_at(Tr.of(), 10)))),
     b1("usb_open_refused_beyond_11", Tr.refused(usb_open(True{}, True{}, Tr.fail_at(Tr.of(), 11)))),
     b1("usb_open_ok_norefs", Tr.refused(usb_open(True{}, False{}, Tr.of()))),
     # the ENUMERATION's checked/RAW split: emit 2 of a one-device HIT is the
     # descriptor read and can refuse; emit 6 is `libusb_free_device_list`, which is
     # RAW, so it cannot -- one row apart and they disagree.
     b1("usb_enum_refused_2_is_checked", Tr.refused(usb_enum(1, True{}, 3, 7, Tr.fail_at(Tr.of(), 2)))),
     b1("usb_enum_refused_5_is_checked", Tr.refused(usb_enum(1, True{}, 3, 7, Tr.fail_at(Tr.of(), 5)))),
     b1("usb_enum_refused_5_fires", Tr.refused(usb_enum(1, True{}, 3, 7, Tr.fail_at(Tr.of(), 5)))),
     b1("usb_enum_refused_6_raw_no_fire", Tr.refused(usb_enum(1, True{}, 3, 7, Tr.fail_at(Tr.of(), 6)))),
     b1("usb_enum_refused_beyond_7", Tr.refused(usb_enum(1, True{}, 3, 7, Tr.fail_at(Tr.of(), 7)))),
     b1("usb_enum_ok_norefs", Tr.refused(usb_enum(1, True{}, 3, 7, Tr.of()))),
     # the ENUMERATION's negative case: a MISS emits the descriptor read and NONE
     # of the ref triple, so it is FOUR calls shorter than a hit and not three.
     s1("usb_enum_order_1_miss_full", Tr.sym(usb_enum(1, False{}, 0, 0, Tr.of())))]))
'''

# the inventory rows go into t_trace
inv = ("     # THE SEAM'S INVENTORY IN THE PORT'S OWN VOCABULARY: each `K_*` and the\n"
       "     # symbol it names. `usb-symmap.py` proves the mapping is a BIJECTION onto\n"
       "     # `SYMS()` and that every symbol is a real libusb export; these rows are\n"
       "     # what a transposed `K_*` ladder would move.\n")
for k in ["init", "set_option", "get_devlist", "get_desc", "ref_device",
          "bus_number", "dev_address", "free_devlist", "open", "get_device",
          "str_ascii", "kdrv_active", "detach_kdrv", "reset_device",
          "set_config", "claim_iface", "set_alt", "ctrl_xfer", "bulk_xfer",
          "alloc_xfer", "events", "submit_xfer", "memcpy", "strerror"]:
    inv += '     s1("usb_inventory_%s", call_sym(K_%s())),\n' % (k, k.upper())
inv += ('     u1("usb_inventory_len", U32.from_nat(List.length(&2, String, SYMS()))),\n'
        '     s1("usb_inventory_past_end", sym_at(24n, SYMS())),\n')
rows = rows.replace('     s1("usb_list_label_b3_a7", list_label(3, 7)),',
                    inv + '     s1("usb_list_label_b3_a7", list_label(3, 7)),')

# the row builders the trace section needs, before it
HELPERS = '''def sym_at.go(n: Nat, ss: List<&2, String>) -> String:
  match n:
    case 0n:
      match ss:
        case Nil{}: "libusb_unknown"
        case h0 <> t2: sym_at_head(h0, t2)
    case 1n+m:
      match ss:
        case Nil{}: "libusb_unknown"
        case h0 <> t2: sym_at.go(m, t2)

# THE HEAD-AT-ZERO ARM IS ITS OWN DEF so `M31`'s off-by-one edit COMPILES: answering
# `head_name(t2, "")` instead of `h0` names the symbol AFTER the one it meant, and
# every COUNT in the file stays right.
#
# IT RETURNS `h0` UNCONDITIONALLY, and that is not a simplification. A version that
# made it `Bool.pick(is_empty(t2), head_name(t2, ""), h0)` read the TAIL's head for
# every index whose tail is non-empty: right at index 23 of 24, wrong at every
# index below it, and a count of symbols sees neither.
def sym_at_head(+h0: String, +t2: List<&2, String>) -> String: h0

# The tail's head. It exists so `M31`'s edit compiles and it is NOT on the live
# path.
def head_name(xs: List<&2, String>, dflt: String) -> String:
  match xs:
    case Nil{}: dflt
    case h <> t: h

# `n` IS THE INDEX and the head is the ZERO-th entry. The version that matched
# `1n+m` and returned the head when `m == 0n` was off by one, and every order row in
# the file read as the symbol BELOW the truth -- exactly the error a count-only
# gate cannot see and a whole-value row can.
def sym_at(+n: Nat, ss: List<&2, String>) -> String: sym_at.go(n, ss)

def call_sym(+k: U32) -> String: sym_at(U32.to_nat(k), SYMS())

def Call.sym(x: Call) -> String: call_sym(Call.k(x))

'''
trace = HELPERS + trace

body = trace + strings + rows

anchor = "# ===========================================================================\n# THE ENTRY POINT."
assert anchor in s
s = s.replace(anchor, body + "\n" + anchor, 1)
io.open(P, "w").write(s)
print("inserted", len(body.split(chr(10))), "lines")