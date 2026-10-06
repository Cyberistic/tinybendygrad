import io

# `t_strings` in ONE FLAT LIST. The grouped form needs a
# `List<&2, List<&2, String>>` whose head type is a list, and Bend's parser closes
# the outer literal on the inner `[` -- the groups are exactly the shape `<>` and
# `List.concat` want and a LITERAL does not. Flat is also cheaper to read.
P = ".agents/slop/usb-sblock.bend.txt"
s = io.open(P).read()

prods = [("usb_prod_custom_x", "custom asic"), ("usb_prod_as2462_x", "AS2462 fw"),
         ("usb_prod_lower_x", "Custom asic"), ("usb_prod_none_x", "Acme Rocket"),
         ("usb_prod_empty_x", "")]
rows = []
for nm, txt in prods:
    rows.append('     s1("%s", "%s")' % (nm, txt))
    for k, lit in (("custom", "custom"), ("as2462", "AS2462")):
        rows.append('     b1("%s_%s", String.starts_with("%s", "%s"))' % (nm, k, txt, lit))
    rows.append('     b1("%s_either", product_ok("%s"))' % (nm, txt))
for st in range(8):
    nm = "usb_cpl_%d" % st
    rows.append('     u1("%s_unsup", Bool.to_u32(U32.is_eq(%d, CPL_UNSUP())))' % (nm, st))
    rows.append('     u1("%s_retry", Bool.to_u32(U32.is_eq(%d, CPL_RETRY())))' % (nm, st))
    rows.append('     u1("%s_abort", Bool.to_u32(U32.is_eq(%d, CPL_ABORT())))' % (nm, st))
    rows.append('     b1("%s_named", cpl_named(%d))' % (nm, st))
    rows.append('     s1("%s_name", cpl_name(%d))' % (nm, st))
msgs = [("usb_msg_bulk_out", "MSG_BULK_OUT()"), ("usb_msg_bulk_in", "MSG_BULK_IN()"),
        ("usb_msg_short_write", "MSG_SHORT_WRITE()"), ("usb_msg_bytes", "MSG_BYTES()"),
        ("usb_msg_tlp_retries", "MSG_TLP_RETRIES()"), ("usb_msg_tlp_cpl", "MSG_TLP_CPL()"),
        ("usb_msg_cpl_unsup", "MSG_CPL_UNSUP()"), ("usb_msg_cpl_abort", "MSG_CPL_ABORT()"),
        ("usb_msg_cpl_retry", "MSG_CPL_RETRY()"), ("usb_msg_cpl_reserved", "MSG_CPL_RESERVED()"),
        ("usb_msg_ltssm", "MSG_LTSSM()"), ("usb_msg_ltssm_tail", "MSG_LTSSM_TAIL()"),
        ("usb_msg_invalid_size", "MSG_INVALID_SIZE()"),
        ("usb_msg_aligned_size_w", "MSG_ALIGNED_SIZE_W()"),
        ("usb_msg_aligned_size_r", "MSG_ALIGNED_SIZE_R()"),
        ("usb_msg_aligned_access_r", "MSG_ALIGNED_ACCESS_R()"),
        ("usb_msg_aligned_access_w", "MSG_ALIGNED_ACCESS_W()"), ("usb_msg_sz", "MSG_SZ()"),
        ("usb_msg_checked", "MSG_CHECKED()"), ("usb_product_ok", "PRODUCT_OK()"),
        ("usb_product_ok2", "PRODUCT_OK2()")]
for nm, ex in msgs:
    rows.append('     s1("%s", %s)' % (nm, ex))

TSTR = """# THE STRING ROWS. Every literal is DIFFED AS A STRING: a row that said "the
# message is non-empty" would stay green with the prefix removed, and
# `String.concat` drops a literal silently.
#
# ONE FLAT LIST, not a fold over per-fixture GROUPS. A `List<&2, List<&2, String>>`
# is exactly the shape `<>` and `List.concat` want and a LITERAL does not, and
# Bend's parser closes the outer literal on the inner `[`.
def t_strings() -> IO(Unit):
  IO.print(lines_of(
    [
""" + ",\n".join(rows) + """]))

"""

# THE CUT STARTS AT THE BANNER AND NOT AT THE `def`, because the banner is
# ABOVE the `def`: cutting from the `def` leaves the old banner in place and every
# run of this script appends another copy, which is a defect that only shows up as
# a file that grows each time the pipeline runs.
i = s.index("# THE STRING ROWS.")
j = s.index("def t_packets() -> IO(Unit):")
s = s[:i] + TSTR + s[j:]
io.open(P, "w").write(s)
print("flat t_strings rebuilt")