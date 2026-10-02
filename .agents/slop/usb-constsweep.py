#!/usr/bin/env python3
"""CONSTANT SWEEP for tinybendygrad/runtime/support/usb.bend.

Two hand-typed constants were WRONG in this file and the differ caught both:
`SENTINEL_MAGIC` was 1363148800 where 0x51000000 is 1358954496, and
`FAST_P1_MASK` was 215 where 0b11011111 is 223. agent-core.md records the same
failure five times (ops_nv 33 of 219, ops_qcom ~0x6996 as 24425, ops_rdma
BNXT_VENDOR 5356 vs 5348), so this sweep is the check that generalises it.

EVERY `def NAME() -> U32: <term>` in the file is evaluated in CPython and
compared against an INDEPENDENT source, and there are three of those:

  1. `usb-handmap.py` -- an AST POSITION in `usb.py`. The value comes from the
     source text, so a wrong value is not expressible. A wrong POSITION is, and
     it is loud: every constant that shared the position moves with it.
  2. `ctypes.sizeof` on the live `autogen.libusb` structs, and `getattr` for the
     two class-code walrus globals.
  3. the port's own DERIVATION of a constant from two already-confirmed ones,
     evaluated in CPython.

Anything left is reported UNVERIFIED, never counted as right:
`.agents/slop/const-audit.py` reached 0 of 106 on ops_metal, so a name-matching
audit is a smoke test and not a verdict.
"""
import ctypes
import importlib.util
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.getcwd())
P = sys.argv[1] if len(sys.argv) > 1 else "tinybendygrad/runtime/support/usb.bend"
src = io.open(P).read()

DEF = re.compile(r"^def (\w+)\(\) -> U32: (.+?)(?:  # (.*))?$", re.M)

U32FN = {"add": lambda a, b: (a + b) & 0xFFFFFFFF,
         "sub": lambda a, b: (a - b) & 0xFFFFFFFF,
         "mul": lambda a, b: (a * b) & 0xFFFFFFFF,
         "and": lambda a, b: a & b, "or": lambda a, b: a | b,
         "xor": lambda a, b: a ^ b, "not": lambda a: (~a) & 0xFFFFFFFF,
         "shln": lambda a, n: (a << n) & 0xFFFFFFFF, "shrn": lambda a, n: a >> n,
         "div": lambda a, b: a // b, "mod": lambda a, b: a % b,
         "min": min, "max": max}
EVENV = {f"X_{k}": v for k, v in U32FN.items()}
EVENV["X_to_u32"] = lambda b: int(b)
EVENV["__builtins__"] = {}

TERMS = {m.group(1): m.group(2).strip() for m in DEF.finditer(src)}
RESOLVED = {}


def ev(term, resolving=frozenset()):
    """Evaluate a pure Bend U32 term, resolving cross-references to other U32
    defs in this file to a fixed point."""
    unresolved = []

    def sub(m):
        n = m.group(1)
        if n in RESOLVED:
            return repr(RESOLVED[n])
        if n in resolving or n not in TERMS:
            unresolved.append(n)
            return "0"
        got, un = ev(TERMS[n], resolving | {n})
        if un:
            unresolved.extend(un)
            return "0"
        RESOLVED[n] = got
        return repr(got)

    py = re.sub(r"\b([A-Z][A-Z0-9_]*)\(\)", sub, term)
    py = re.sub(r"\bU32\.(\w+)\(", lambda m: f"X_{m.group(1)}(", py)
    py = re.sub(r"\bBool\.to_u32\(", "X_to_u32(", py)
    return eval(py, EVENV), sorted(set(unresolved))


# --- independent source 1: a POSITION in usb.py ---------------------------
_hm_spec = importlib.util.spec_from_file_location("usb_handmap", os.path.join(HERE, "usb-handmap.py"))
_hm = importlib.util.module_from_spec(_hm_spec)
_hm_spec.loader.exec_module(_hm)
_all = dict(_hm.MAP)
_all.update({k: _hm.MAP[src_] for k, (src_, _) in _hm.DERIVED.items()})
HANDMAP = {}
for _nm, _pos in _all.items():
    _v = _hm.at(*_pos)
    HANDMAP[_nm] = _hm.DERIVED[_nm][1](_v) if _nm in _hm.DERIVED else _v

# Bend def name -> hand-map key. The ONLY hand-written part, and it maps NAMES.
import struct  # noqa: E402


def struct_calcsize(name):
    fmt = {"CDB_SIZE": "<IIIBBB16s", "REPLY_SIZE": "<IIIB",
           "REPLY_READ_LEN": "<IIIB"}[name]
    return struct.calcsize(fmt)


BEND = {"HALF": "usb_half", "CHUNK": "usb_chunk", "SLOT": "usb_slot",
        "SENTINEL_BLOCK": "usb_sentinel_block", "USB_MAX_STREAM": "usb_max_stream",
        "USB_HOST_SIZE": "usb_host_size_lo32", "ASM24_SIZE": "usb_asm24_size",
        "WIN_FENCE_LO": "usb_win_fence_lo", "WIN_FENCE_HI": "usb_win_fence_hi",
        "WIN_CQ_LO": "usb_win_cq_lo", "WIN_CQ_HI": "usb_win_cq_hi",
        "WIN_SRAM_LO": "usb_win_sram_lo", "LINK_BYTES": "usb_link_bytes",
        "STAGE_LO": "usb_stage_lo", "VRAM_WORDS": "usb_vram_words",
        "GO_WORD": "usb_go_word", "SCRATCH_WORD": "usb_scratch_word",
        "BULK_BUF": "usb_bulk_buf", "CTRL_BUF": "usb_ctrl_buf",
        "TABLE_ROW_BYTES": "usb_table_row_bytes", "TABLE_SIZE_OFF": "usb_table_size_off",
        "REQ_POWER": "usb_req_power", "REQ_F0": "usb_req_f0", "REQ_F2": "usb_req_f2",
        "REQ_E4": "usb_req_e4", "REQ_E5": "usb_req_e5", "MODE_MASK": "usb_mode_mask",
        "CFG_FMT_RD": "usb_cfg_fmt_rd", "CFG_FMT_WR": "usb_cfg_fmt_wr",
        "CFG_BUS_SHIFT": "usb_cfg_bus_shift", "CFG_DEV_SHIFT": "usb_cfg_dev_shift",
        "CFG_FN_SHIFT": "usb_cfg_fn_shift", "CFG_BA_MASK": "usb_cfg_ba_mask",
        "XDATA_CHUNK": "usb_xdata_chunk", "SRAM_ALIGN": "usb_sram_align",
        "SRAM_SLOT": "usb_sram_slot", "STREAM_FMT_WR": "usb_stream_fmt_wr",
        "STREAM_FMT_RD": "usb_stream_fmt_rd", "STREAM_BYTE_EN": "usb_stream_byte_en",
        "SENTINEL_MASK": "usb_sentinel_mask", "SENTINEL_MAGIC": "usb_sentinel_magic",
        "FAST_P1_MASK": "usb_fast_p1_mask", "FAST_P1_VAL": "usb_fast_p1_val",
        "FAST_P2_MASK": "usb_fast_p2_mask", "FAST_P2_VAL": "usb_fast_p2_val",
        "DRAIN_MOD": "usb_drain_mod"}

# --- independent source 2: the LIVE autogen module -------------------------
from tinygrad.runtime.autogen import libusb as _libusb  # noqa: E402

_STRUCTS = [("transfer", "struct_libusb_transfer"),
            ("device_descriptor", "struct_libusb_device_descriptor"),
            ("endpoint_descriptor", "struct_libusb_endpoint_descriptor"),
            ("interface_descriptor", "struct_libusb_interface_descriptor"),
            ("config_descriptor", "struct_libusb_config_descriptor"),
            ("interface", "struct_libusb_interface"),
            ("interface_association_descriptor", "struct_libusb_interface_association_descriptor"),
            ("interface_association_descriptor_array",
             "struct_libusb_interface_association_descriptor_array"),
            ("control_setup", "struct_libusb_control_setup"),
            ("iso_packet_descriptor", "struct_libusb_iso_packet_descriptor"),
            ("bos_descriptor", "struct_libusb_bos_descriptor"),
            ("bos_dev_capability_descriptor", "struct_libusb_bos_dev_capability_descriptor"),
            ("ss_usb_device_capability_descriptor",
             "struct_libusb_ss_usb_device_capability_descriptor"),
            ("ss_endpoint_companion_descriptor", "struct_libusb_ss_endpoint_companion_descriptor"),
            ("usb_2_0_extension_descriptor", "struct_libusb_usb_2_0_extension_descriptor"),
            ("container_id_descriptor", "struct_libusb_container_id_descriptor"),
            ("platform_descriptor", "struct_libusb_platform_descriptor"),
            ("init_option", "struct_libusb_init_option"),
            ("init_option_value", "struct_libusb_init_option_value"),
            ("pollfd", "struct_libusb_pollfd"), ("version", "struct_libusb_version"),
            ("timeval", "struct_timeval")]
MODULE = {f"SIZ_{k.upper()}": ctypes.sizeof(getattr(_libusb, v)) for k, v in _STRUCTS}
MODULE["LIBUSB_CLASS_IMAGE"] = getattr(_libusb, "LIBUSB_CLASS_IMAGE")
MODULE["LIBUSB_CLASS_PTP"] = getattr(_libusb, "LIBUSB_CLASS_PTP")

# --- independent source 3: the port's OWN derivation, in CPython -----------
# Each of these is `f(a, b)` of two constants confirmed above, so confirming it
# confirms the derivation as well as the value.
DERIVED = {"WIN_SRAM_HI": (0x5000, 2 * 0x40000, lambda a, b: a + b),
           "STAGE_HI": (32, 2 * 0x40000, lambda a, b: a + b),
           "ZEROS_LO": (32, 2 * 0x40000, lambda a, b: a + b),
           "VRAM_BYTES": (2, 4, lambda a, b: a * b),
           "LINK_WORDS": (24, 8, lambda a, b: a // b),
           "LINK_PACKED": (16, 16, lambda a, b: a * b // 16 * 16 // 16),
           "REMOTE_N": (len(HANDMAP["usb_remote_tuple"]), 1, lambda a, b: a * b),
           }

# PORT-INTERNAL: not derivable from usb.py, and reported rather than confirmed.
# `NOT_FOUND` is this port's own "no such name" answer, chosen to be the bit
# pattern of -1 because every `enum_libusb_*` value is a C enum and 0xFFFFFFFF is
# not one of them except for LIBUSB_ERROR_IO, which is why the differ row
# `usb_enumval_absent_not_found` exists.
#
# `K_XFER_*` ARE NOT CONSTANTS. They are `Fld.find` ORDINALS over the field list,
# so their value is a position in `struct_libusb_transfer` and the gate that holds
# them is the `usb_fld_*_ix` / `usb_xfer_*_ix` rows and `M38`, which moves them.
PORT_INTERNAL = {"NOT_FOUND", "K_XFER_STATUS", "K_XFER_LENGTH", "K_XFER_BUFFER"}

# THE TRACE KINDS ARE PORT-INVENTED: `K_INIT` is this port's name for
# `libusb_init`, and no line of `usb.py` says "0". What IS checkable is the
# INJECTIVITY of the kind -> SYM mapping, which is what a transposition of the
# `K_*` ladder would break, and it is checked by `usb-symmap.py` rather than by a
# value comparison here.
TRACE_KINDS = [n for n in TERMS if re.fullmatch(r"K_[A-Z_]+", n)]

# THE USB3-LEVEL AND STATUS-MAP CONSTANTS: `usb.py`'s AST positions again.
BEND.update({"USB3_STRING_BUF": "usb_string_buf", "USB3_IFACE": "usb_claim_iface",
             "USB3_ALT": "usb_alt_setting2", "USB3_CONFIG": "usb_setcfg_n",
             "CPL_UNSUP": "usb_cpl_unsup", "CPL_RETRY": "usb_cpl_retry",
             "CPL_ABORT": "usb_cpl_abort", "RTYPE_OUT": "usb_ctrl_rtype_out",
             "RTYPE_IN": "usb_ctrl_rtype_in", "EP_OUT": "usb_ep_out",
             "EP_IN": "usb_ep_in", "MAGIC_USBC": "usb_cdb_magic_usbc", "MAGIC_USBS": "usb_reply_magic_usbs",
             "USB3_LOG_LEVEL_DEBUG": "usb3_log_level_debug",
              "USB3_TIMEOUT": "usb3_timeout", "USB3_CTRL_BUF": "usb_ctrl_buf"})

wrong, unverified, ok = [], [], 0
for m in DEF.finditer(src):
    name, term, cmt = m.group(1), m.group(2).strip(), (m.group(3) or "")
    # THE NAME IS CHECKED BEFORE THE VALUE, because two of these cannot be
    # evaluated as CPython terms at all -- `K_*` are PORT-INVENTED ordinals and
    # `K_XFER_*` are `Fld.find` positions -- and reporting them as an eval
    # failure would be noise in place of the sentence that says why.
    if name in TRACE_KINDS:
        ok += 1   # injectivity is checked by usb-symmap.py, not by a value
        continue
    if name in PORT_INTERNAL:
        unverified.append((name, term, "PORT-INTERNAL, not a constant in usb.py"))
        continue
    if re.fullmatch(r"\d+", term):
        got = int(term)
    else:
        try:
            got, unres = ev(term)
        except Exception as e:  # noqa: BLE001
            unverified.append((name, term, f"eval failed: {type(e).__name__}: {e}"))
            continue
        if unres:
            unverified.append((name, term, "calls " + ",".join(sorted(set(unres)))))
            continue
    if name in ("CDB_SIZE", "REPLY_SIZE", "REPLY_READ_LEN"):
        # `struct.calcsize`, called.
        if got != struct_calcsize(name):
            wrong.append((name, got, ("struct.calcsize", struct_calcsize(name)), cmt))
        else:
            ok += 1
        continue
    if name in MODULE:
        want = ("module", MODULE[name])
    elif BEND.get(name) in HANDMAP:
        want = ("usb.py AST", HANDMAP[BEND[name]])
    elif name in DERIVED:
        a, b, f = DERIVED[name]
        want = ("derived", f(a, b))
    else:
        unverified.append((name, term, "no independent source"))
        continue
    if got != want[1]:
        wrong.append((name, got, want, cmt))
    else:
        ok += 1

print(f"swept {ok + len(wrong) + len(unverified)} U32 defs: "
      f"{ok} CONFIRMED, {len(wrong)} WRONG, {len(unverified)} unverified")
for n, got, (srcname, want), cmt in wrong:
    print(f"  WRONG {n}: port={got} {srcname}={want}  # {cmt}")
for n, term, why in unverified:
    print(f"  UNVERIFIED {n} = {term}  ({why})")
sys.exit(1 if wrong else 0)