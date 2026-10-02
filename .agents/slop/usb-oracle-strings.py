#!/usr/bin/env python3
"""CPython oracle for the STRING and PACKET rows of tinybendygrad/runtime/support/usb.bend.

Every string is read out of `usb.py`'s AST as a LITERAL node, so a row that
dropped a character or reordered two words is caught -- `String.concat` drops a
literal silently, and a boolean about a string cannot see that happen.

The packet rows come from `struct.calcsize` and `struct.pack`, never from a count
by eye: `"<IIIBBB16s"` is 31 bytes and `"<IIIB"` is 13, which is exactly the
`bulk_read(13)` on the next line of `usb.py`.
"""
import ast
import io
import os
import struct
import sys

sys.path.insert(0, os.getcwd())

SRC = "tinygrad/runtime/support/usb.py"
TREE = ast.parse(io.open(SRC).read())
OUT = []


def s(nm, v):
    OUT.append(f"{nm}={v}")


def b(nm, v):
    OUT.append(f"{nm}={'True' if v else 'False'}")


def u(nm, v):
    OUT.append(f"{nm}={v}")


def all_strings():
    got = []
    for node in ast.walk(TREE):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            got.append(node.value)
    return got


STRINGS = all_strings()

# The f-string PARTS: for each JoinedStr, the constant pieces in order. An
# f-string's literal pieces are exactly what `String.concat` has to reproduce.
FPARTS = []
for node in ast.walk(TREE):
    if isinstance(node, ast.JoinedStr):
        parts = [v.value for v in node.values
                 if isinstance(v, ast.Constant) and isinstance(v.value, str)]
        if parts:
            FPARTS.append(parts)


def has(text):
    return text in STRINGS or any(text in p for p in FPARTS)


# --- the plain literals the port rows --------------------------------------
for nm, txt in [
    ("bulk_out", "bulk OUT 0x02 failed"),
    ("bulk_in", "bulk IN 0x81 failed"),
    ("short_write", "bulk OUT short write: "),
    ("bytes", " bytes"),
    ("tlp_retries", "TLP error after retries: ret_status="),
    ("tlp_cpl", "TLP completion status: "),
    ("cpl_unsup", "Unsupported Request: "),
    ("cpl_abort", "Completer Abort"),
    ("cpl_retry", "Config Retry"),
    ("cpl_reserved", "Reserved (0b"),
    ("ltssm", "PCIe link not up (LTSSM=0x"),
    ("ltssm_tail", "), custom firmware not ready"),
    ("invalid_size", "Invalid size "),
    ("aligned_size_w", "pcie_mem_write requires 4-byte aligned size, got "),
    ("aligned_size_r", "pcie_mem_read requires 4-byte aligned size, got "),
    ("aligned_access_r", "pcie_mem_read requires 4-byte aligned access, got off="),
    ("aligned_access_w", "pcie_mem_write requires 4-byte aligned access, got off="),
    ("sz", ", sz="),
    ("checked", ": "),
    ("product_ok", "custom"),
    ("product_ok2", "AS2462"),
]:
    # the row's VALUE is the literal, and CPython says whether `usb.py` HAS it:
    # a port that dropped or reordered a character answers MISSING-FROM-USB.PY
    # here, so the differ catches a `String.concat` that lost a word.
    row = f"usb_product_ok{nm[len('product_ok'):]}" if nm.startswith("product_ok") else f"usb_msg_{nm}"
    s(row, txt if has(txt) else "MISSING-FROM-USB.PY")

# --- :52 the product assert, evaluated in CPython --------------------------
PRODUCTS = ["custom asic", "AS2462 fw", "Custom asic", "Acme Rocket", ""]
for nm, prod in [("custom_x", "custom asic"), ("as2462_x", "AS2462 fw"),
                 ("lower_x", "Custom asic"), ("none_x", "Acme Rocket"),
                 ("empty_x", "")]:
    s(f"usb_prod_{nm}", prod)
    b(f"usb_prod_{nm}_custom", prod.startswith("custom"))
    b(f"usb_prod_{nm}_as2462", prod.startswith("AS2462"))
    b(f"usb_prod_{nm}_either",
      prod.startswith("custom") or prod.startswith("AS2462"))

# --- :132 the completion status map, as a REAL dict lookup ----------------
STATUS_MAP = {0b001: "Unsupported Request", 0b100: "Completer Abort", 0b010: "Config Retry"}
# the port renders the LABEL, so strip the f-string's field from the source text
for st in range(8):
    nm = f"usb_cpl_{st}"
    u(f"{nm}_unsup", int(st == 0b001))
    u(f"{nm}_retry", int(st == 0b010))
    u(f"{nm}_abort", int(st == 0b100))
    b(f"{nm}_named", st in STATUS_MAP)
    s(f"{nm}_name", ("Unsupported Request: " if st == 0b001 else
                     "Config Retry" if st == 0b010 else
                     "Completer Abort" if st == 0b100 else "Reserved (0b"))

# --- the packet formats ----------------------------------------------------
CDB_FMT, REPLY_FMT = "<IIIBBB16s", "<IIIB"
s("usb_cdb_fmt", CDB_FMT)
s("usb_cdb_fields", "magic tag datalen zero0 zero1 cdblen cdb")
# the WIDTHS come from calcsize of each field's own format, and they must sum to
# the whole -- a reader who counts 16s as four uint32 gets 39 and not 31.
def widths(fmt):
    """Per-field widths, from a SPLIT of the format into (count, code) pairs.
    Iterating the format character by character does not work: `16s` is TWO
    characters and `struct.calcsize("1")` is a repeat-count error."""
    import re
    return " ".join(str(struct.calcsize(cnt + code)) for cnt, code in re.findall(r"(\d*)([a-zA-Z])", fmt))


s("usb_cdb_widths", widths("<IIIBBB16s"))
u("usb_cdb_size", struct.calcsize(CDB_FMT))
s("usb_reply_fmt", REPLY_FMT)
s("usb_reply_fields", "sig rtag discard status")
s("usb_reply_widths", widths(REPLY_FMT))
u("usb_reply_size", struct.calcsize(REPLY_FMT))

# :89 the CDB, packed for real: 31 bytes, and the two magics at both ends.
cdb = struct.pack(CDB_FMT, 0x43425355, 7, 0, 0, 0, 4, b"\x01\x02\x03\x04")
u("usb_cdb_packed_len", len(cdb))
u("usb_magic_usbc", 0x43425355)
u("usb_magic_usbs", 0x53425355)
# :91's `bulk_read(13)` and the reply's `calcsize` are THE SAME NUMBER.
u("usb_reply_read_len", struct.calcsize(REPLY_FMT))
# :92 `(sig, rtag, status) == (0x53425355, tag, 0)`
for nm, sig, rtag, status, tag in [("exact", 0x53425355, 7, 0, 7),
                                   ("wrong_tag", 0x53425355, 8, 0, 7),
                                   ("nonzero_status", 0x53425355, 7, 1, 7),
                                   ("wrong_sig", 0x43425355, 7, 0, 7),
                                   ("all_wrong", 0, 0, 1, 9)]:
    b(f"usb_reply_ok_{nm}", (sig, rtag, status) == (0x53425355, tag, 0))
# :91's real reply, unpacked, so the field NAMES have something to name
sig, rtag, _discard, status = struct.unpack(REPLY_FMT, struct.pack(REPLY_FMT, 0x53425355, 7, 0, 0))
u("usb_reply_unpacked_sig", sig)
u("usb_reply_unpacked_rtag", rtag)
u("usb_reply_unpacked_status", status)

# --- the request types and endpoints ---------------------------------------
u("usb_rtype_out", 0x40)
u("usb_rtype_in", 0xC0)
u("usb_ep_out", 0x02)
u("usb_ep_in", 0x81)
u("usb_ep_out_dir", 0x02 & 0x80)
u("usb_ep_in_dir", 0x81 & 0x80)
# and the DIRECTION bit is `LIBUSB_ENDPOINT_IN`, which is 128
u("usb_ep_in_is_libusb_endpoint_in",
  int(0x81 & 0x80 == getattr(__import__("tinygrad.runtime.autogen.libusb", fromlist=["x"]),
                             "LIBUSB_ENDPOINT_IN")))
# the two rtypes differ ONLY in the direction bit: 0x40 | 0x80 == 0xC0
u("usb_rtype_in_is_out_or_direction", int(0x40 | 0x80 == 0xC0))

# --- the USB3-level constants the trace names ------------------------------
u("usb3_string_buf", 256)
u("usb3_iface", 0)
u("usb3_alt", 0)
u("usb3_config", 1)
u("usb3_log_level_debug", 4)

# --- the `usb:` enumeration label, formatted for real ----------------------
s("usb_list_label_b3_a7", f"usb:{3}-{7}")
s("usb_list_label_b0_a0", f"usb:{0}-{0}")
s("usb_list_label_b255_a127", f"usb:{255}-{127}")

sys.stdout.write("\n".join(OUT) + "\n")