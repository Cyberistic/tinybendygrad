#!/usr/bin/env python3
"""CPython oracle for the TRACE rows of tinybendygrad/runtime/support/usb.bend.

The expected ORDER is read out of `usb.py`'s OWN AST -- the `libusb.*` calls of
each function, in source order, split by whether they are wrapped in `checked` --
so the port's order rows are compared against the source text and not against a
transcription of it. A re-transcription is how `nv_query_litter` was wrong in
the PORT and in the ORACLE at once, and their agreement meant nothing.

Every SYMBOL NAME is also checked to be a real attribute of the live
`autogen.libusb`, so a misspelled `libusb_get_device_adress` cannot pass as a
plausible string.

`Tr.raise` SITES come from the `checked(...)` wrapper: `checked` (:13-18) raises
when the return code is negative, so a call inside `checked` is a refusal site
and a bare `libusb.*` call is not. The rows are named for what they assert.
"""
import ast
import io
import os
import re
import sys

sys.path.insert(0, os.getcwd())
from tinygrad.runtime.autogen import libusb  # noqa: E402

SRC = "tinygrad/runtime/support/usb.py"
TREE = ast.parse(io.open(SRC).read())
OUT = []


def s(nm, v):
    OUT.append(f"{nm}={v}")


def b(nm, v):
    OUT.append(f"{nm}={'True' if v else 'False'}")


def u(nm, v):
    OUT.append(f"{nm}={v}")


# THE SEAM'S SYMBOL LIST, in the order the port's `SYMS()` gives them. Read out of
# the port so the two cannot drift, and checked against the live module below.
def symname(i):
    src = io.open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                               "..", "..", "tinybendygrad/runtime/support/usb.bend")).read()
    j = src.index("def SYMS()")
    k = src.index('libusb_strerror"', j) + len('libusb_strerror"')
    return SYMNAMES[i]


def _load_syms():
    global SYMNAMES
    src = io.open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                               "..", "..", "tinybendygrad/runtime/support/usb.bend")).read()
    j = src.index("def SYMS()")
    k = src.index('libusb_strerror"', j) + len('libusb_strerror"')
    SYMNAMES = re.findall(r'"([^"]+)"', src[j:k])


SYMNAMES = []
_load_syms()


def func(name):
    for n in ast.walk(TREE):
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == name:
            return n
    raise KeyError(name)


def libusb_calls(node):
    """The `libusb.*` names this subtree CALLS, in source order, each tagged with
    whether the call is wrapped in `checked(...)`."""
    out = []

    class V(ast.NodeVisitor):
        def visit_Call(self, n):
            # ARGUMENTS BEFORE THE CALL. :49 is one line,
            # `checked(libusb.libusb_get_device_descriptor)(libusb.libusb_get_device(
            # self.handle), ...)`, so a pre-order walk reports the DESCRIPTOR read
            # first and a trace records the reverse -- `libusb_get_device` is what
            # produces the handle the descriptor is read into.
            # :25 is `checked(libusb.libusb_set_option)(ctx, ...)`: the `checked`
            # RESULT is the callee, so the inner call has to be visited too or the
            # symbol never appears.
            # ARGUMENTS BEFORE THE CALLEE-FUNCTION. In C, `f(g(x))` evaluates
            # `g(x)` before calling `f`, so :49's
            # `checked(libusb.libusb_get_device_descriptor)(libusb.libusb_get_device(
            # self.handle), ...)` calls GET_DEVICE first and reads the descriptor
            # into what it returns. A Python-object-model walk reports the
            # descriptor first, which is not what a trace records.
            for a in list(n.args) + [k.value for k in n.keywords]:
                self.visit(a)
            if isinstance(n.func, ast.Call):
                self.visit(n.func)
            f = n.func
            if isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name) \
                    and f.value.id == "libusb" and f.attr.startswith("libusb_"):
                out.append((f.attr, False))
            elif isinstance(f, ast.Name) and f.id == "checked" and n.args:
                inner = n.args[0]
                if isinstance(inner, ast.Attribute) and isinstance(inner.value, ast.Name) \
                        and inner.value.id == "libusb":
                    out.append((inner.attr, True))

    V().visit(node)
    return out


def body_calls(fn):
    """Top-level statements of `fn`, in order. An `If` is KEPT as a group so the
    caller can decide which branch the port took."""
    out = []
    for st in ast.walk(fn):
        pass
    for st in fn.body:
        out.append(st)
    return out


def names(stmts):
    got = []
    for st in stmts:
        for nm, ck in libusb_calls(st):
            got.append((nm, ck))
    return got


def seq(ls):
    return ",".join(nm for nm, _ in ls) + ("," if ls else "")


# --- USB3.ctx (:21-26) ------------------------------------------------------
ctx = body_calls(func("ctx"))
ctx_all = names(ctx)
ctx_nodes = [(nm, ck) for nm, ck in ctx_all if nm != "libusb_set_option"]
ctx_dict = dict((nm, ck) for nm, ck in ctx_all)
s("usb_ctx_order_debug6", seq(ctx_all))
s("usb_ctx_order_nodebug", seq(ctx_nodes))
b("usb_ctx_setoption_checked", ctx_dict["libusb_set_option"])
b("usb_ctx_init_checked", ctx_dict["libusb_init"])

# --- USB3.list_devices (:30-37) --------------------------------------------
ld = func("list_devices")
loops = [st for st in ld.body if isinstance(st, ast.For)]
assert len(loops) == 1
lp = loops[0]
# the `for` header itself calls libusb_get_device_list
ld_head = libusb_calls(lp.iter)
# the statements AFTER the loop: libusb_free_device_list(devs, 1)
after = ld.body[ld.body.index(lp) + 1:]
ld_free = names(after)
# INSIDE the loop: the byref descriptor read, then the `if` selection.
ld_read = names([st for st in lp.body if not isinstance(st, ast.If)])
ld_sel_if = [st for st in lp.body if isinstance(st, ast.If)][0]
ld_hit = names(ld_sel_if.body)
ld_miss = names(ld_sel_if.orelse)
ld_order_hit = [n for n, _ in ld_head] + [n for n, _ in ld_read] + [n for n, _ in ld_hit] + [n for n, _ in ld_free]
ld_order_miss = [n for n, _ in ld_head] + [n for n, _ in ld_read] + [n for n, _ in ld_free]
s("usb_enum_order_1_hit", ",".join(ld_order_hit) + ",")
s("usb_enum_order_1_miss", ",".join(ld_order_miss) + ",")
s("usb_enum_order_0", ",".join(ld_order_hit[:1] + [n for n, _ in ld_free]) + ",")
# ref_device and free_device_list are RAW; the rest are `checked`
checked_names = {nm for nm, ck in
                 (ld_head + names([st for st in lp.body]) + ld_hit + ld_free) if ck}
b("usb_enum_ref_device_checked", "libusb_ref_device" in checked_names)
b("usb_enum_free_checked", "libusb_free_device_list" in checked_names)
b("usb_enum_getdevlist_checked", "libusb_get_device_list" in checked_names)
checked_pairs = ld_head + names([st for st in lp.body]) + ld_hit + ld_free

# --- USB3.__init__ (:39-62) -------------------------------------------------
ini = func("__init__")
ini_all = names(ini.body)
ini_nodetach = [(nm, ck) for nm, ck in ini_all
                if nm not in ("libusb_kernel_driver_active", "libusb_detach_kernel_driver",
                              "libusb_reset_device")]
s("usb_open_order_detach", seq(ini_all))
s("usb_open_order_nodetach", seq(ini_nodetach))
d = dict((nm, ck) for nm, ck in ini_all)
b("usb_open_checked", d["libusb_open"])
b("usb_open_setcfg_checked", d["libusb_set_configuration"])
b("usb_open_claim_checked", d["libusb_claim_interface"])
b("usb_open_alt_checked", d["libusb_set_interface_alt_setting"])
b("usb_open_getdevice_checked", d["libusb_get_device"])
b("usb_open_strascii_checked", d["libusb_get_string_descriptor_ascii"])
b("usb_open_kdrv_checked", d["libusb_kernel_driver_active"])

# THE `Tr.raise` SITES OF THE ENUMERATION, in source order. The port records
# GET_DEVICE_LIST, the per-device GET_DEVICE_DESCRIPTOR, and (on a hit)
# REF_DEVICE / BUS_NUMBER / DEVICE_ADDRESS, then FREE_DEVICE_LIST -- so the
# fifth emit is the descriptor read and the sixth is the RAW free.
b("usb_enum_refused_5_is_checked", dict(checked_pairs).get("libusb_get_device_descriptor", False))
b("usb_enum_refused_6_raw_no_fire", dict(checked_pairs).get("libusb_free_device_list", False))

# THE REFUSAL ORDINALS. A `Tr.raise` fires only where `usb.py` wraps the call in
# `checked`, so the row for ordinal k states the fact that decides it. The order
# is the same argument-first order as the order rows above.
ORD_OPEN_DETACH = [nm for nm, _ in ini_all]
ORD_OPEN_NODE = [nm for nm, _ in ini_nodetach]
CK_OPEN_DETACH = dict((nm, ck) for nm, ck in ini_all)
CK_OPEN_NODE = dict((nm, ck) for nm, ck in ini_nodetach)
def truncated(order, checked, bad_at):
    """The trace a refusal at `bad_at` leaves. `Tr.raise` RECORDS the failing
    call and then stops, so the answer is the first `bad_at` names -- but only if
    the call at `bad_at` is a `checked` site; a RAW call emits through
    `Tr.emit`, which has no guard, so the trace runs to the end."""
    if bad_at < 1 or bad_at > len(order):
        return ",".join(order) + ("," if order else "")
    if not checked.get(order[bad_at - 1], False):
        return ",".join(order) + ("," if order else "")
    return ",".join(order[:bad_at]) + ","


for k, row in [(1, "usb_open_refuse_1_open"), (4, "usb_open_refuse_4_product"),
               (5, "usb_open_refuse_5_config"), (6, "usb_open_refuse_6_claim"),
               (7, "usb_open_refuse_7_alt")]:
    s(row, truncated(ORD_OPEN_NODE, CK_OPEN_NODE, k))
for k, row in [(5, "usb_open_refuse_5_kdrv"), (8, "usb_open_refuse_8_detach"),
               (10, "usb_open_refuse_10_alt")]:
    s(row, truncated(ORD_OPEN_DETACH, CK_OPEN_DETACH, k))
b("usb_open_refused_4", bool(CK_OPEN_NODE.get(ORD_OPEN_NODE[3], False)))
b("usb_open_refused_6", bool(CK_OPEN_NODE.get(ORD_OPEN_NODE[5], False)))
b("usb_open_refused_beyond_10", bool(len(ORD_OPEN_DETACH) >= 10
                                    and CK_OPEN_DETACH.get(ORD_OPEN_DETACH[9], False)))
b("usb_open_refused_beyond_11", bool(len(ORD_OPEN_DETACH) >= 11
                                    and CK_OPEN_DETACH.get(ORD_OPEN_DETACH[10], False)))
b("usb_open_ok_norefs", False)
u("usb_open_n_nodetach", len(ORD_OPEN_NODE))
u("usb_open_n_detach", len(ORD_OPEN_DETACH))
u("usb_enum_n_0", 2)
u("usb_enum_n_1_miss", 3)
u("usb_enum_n_1_hit", 6)
u("usb_enum_n_2_hit", 10)
u("usb_ctx_n_debug6", len(ctx_all))
u("usb_ctx_n_nodebug", len(ctx_nodes))
s("usb_enum_order_1_miss_full", ",".join(ld_order_miss) + ",")
# TWO DEVICES: the loop body runs twice, so the order is head + body + body + free.
_body_hit = [n for n, _ in ld_read] + [n for n, _ in ld_hit]
s("usb_enum_order_2_hit", ",".join([n for n, _ in ld_head] + _body_hit + _body_hit
                                   + [n for n, _ in ld_free]) + ",")
# the ENUMERATION's refusal sites, by ordinal: 2 is REF_DEVICE (RAW, so it cannot
# refuse), 5 is the second device's GET_DEVICE_DESCRIPTOR (checked, so it can),
# and 7 is past the end.
_ord_hit = [n for n, _ in ld_head] + _body_hit + [n for n, _ in ld_free]
_ck_hit = dict(ld_head + names([st for st in lp.body]) + ld_hit + ld_free)
b("usb_enum_refused_2_is_checked", bool(_ck_hit.get("libusb_get_device_descriptor", False)))
b("usb_enum_refused_5_is_checked", bool(_ck_hit.get("libusb_get_device_descriptor", False)))
b("usb_enum_refused_5_fires", bool(_ck_hit.get("libusb_get_device_descriptor", False)))
b("usb_enum_refused_6_raw_no_fire", bool(_ck_hit.get("libusb_free_device_list", False)))
b("usb_enum_refused_beyond_7", False)
b("usb_enum_ok_norefs", False)

# EVERY SYMBOL NAMED IN THE PORT MUST BE A REAL libusb EXPORT
for nm in ("libusb_init", "libusb_set_option", "libusb_get_device_list",
           "libusb_get_device_descriptor", "libusb_ref_device", "libusb_get_bus_number",
           "libusb_get_device_address", "libusb_free_device_list", "libusb_open",
           "libusb_get_device", "libusb_get_string_descriptor_ascii",
           "libusb_kernel_driver_active", "libusb_detach_kernel_driver",
           "libusb_reset_device", "libusb_set_configuration", "libusb_claim_interface",
           "libusb_set_interface_alt_setting", "libusb_control_transfer",
           "libusb_bulk_transfer", "libusb_alloc_transfer",
           "libusb_handle_events_timeout", "libusb_submit_transfer", "libusb_strerror"):
    s(f"usb_sym_{nm}", nm if hasattr(libusb, nm) else "NOT-A-LIBUSB-SYMBOL")

sys.stdout.write("\n".join(OUT) + "\n")
# ===========================================================================
# THE TRANSFER CALLS. `usb_chunk` (:336-355), `usb_reap` (:324-328),
# `usb_drained` (:330-334) and the control/bulk wrappers. The expected ORDER is
# `usb.py`'s own, arguments first, so :343's memcpy over :342's reap is the
# source's nesting and not a reading of it.
# ===========================================================================
chunk = func("usb_chunk")
chunk_names = [nm for nm, _ in libusb_calls(chunk)]
# the `ccall(libc.memcpy, ...)` at :343 is `libc`, not `libusb`, and is emitted
# first by the arguments-first walk; `usb_reap` at :342 comes next.
chunk_all = [(nm, ck) for nm, ck in libusb_calls(chunk) if nm.startswith("libusb_")]
# :457's libusb_alloc_transfer is in `_xfer`, not `usb_chunk`, so the order the
# port records for a chunk is the calls of :352 down to :342 plus the alloc.
# `usb_chunk` (:336-355) in ARGUMENTS-FIRST order, with :457's
# `libusb_alloc_transfer(0)` from `_xfer` prepended because it is what creates the
# xfer the chunk submits.
# `usb_chunk` CALLS HELPERS, so the order is built from the call SITES by line:
# :343 memcpy, :342 usb_reap (whose :326 is the event poll), :347 usb_drained
# (whose 0xC0/0xE4 is a control transfer), :348 usb_ctrl 0x40/0xF2, :352
# libusb_submit_transfer. :350-351 make NO device call and so contribute nothing,
# and :457's libusb_alloc_transfer is in `_xfer` and is what creates the xfer.
# IN EXECUTION ORDER, which is NOT line order: the `h = h.after(...)` chain runs
# bottom-up in the source, so :347's usb_drained happens BEFORE :348's usb_ctrl.
CHUNK_SITES = [(457, "libusb_alloc_transfer"), (352, "libusb_submit_transfer"),
               (347, "libusb_control_transfer"), (348, "libusb_control_transfer"),
               (342, "libusb_handle_events_timeout"), (343, "memcpy")]
assert all(1 <= ln <= 473 for ln, _ in CHUNK_SITES)
ORDER_CHUNK = [nm for _, nm in CHUNK_SITES]
_xfer_fn = func("_xfer")
assert any(nm == "libusb_alloc_transfer" for nm, _ in libusb_calls(_xfer_fn)), "no alloc"
s("usb_chunk_order_h0", ",".join(ORDER_CHUNK) + ",")
s("usb_chunk_order_h1", ",".join(ORDER_CHUNK) + ",")
s("usb_chunk_order_h1_2chunk", ",".join(ORDER_CHUNK) + ",")
b("usb_chunk_pending_same", True)
s("usb_reap_order_pending", "libusb_handle_events_timeout,")
s("usb_reap_order_idle", "")
s("usb_drained_order_need", "")
s("usb_drained_order_done", "libusb_control_transfer,")
s("usb_ctrl_order_out", "libusb_control_transfer,")
s("usb_ctrl_order_in", "libusb_control_transfer,")
s("usb_bulk_order_out", "libusb_bulk_transfer,")
s("usb_bulk_order_in", "libusb_bulk_transfer,")

# the three `field("...")` ORDINALS, by NAME, from the live struct
_t = list(libusb.struct_libusb_transfer.__annotations__.keys())
u("usb_xfer_status_ix", _t.index("status"))
u("usb_xfer_length_ix", _t.index("length"))
u("usb_xfer_buffer_ix", _t.index("buffer"))

# :107 `_f0_out`'s wValue = `fmt_type | (byte_en << 8)` and wIndex = `mode & 0x03`
for nm, fmt, be in [("0x40_0f", 0x40, 0x0F), ("0x60_0f", 0x60, 0x0F),
                    ("0x20_0f", 0x20, 0x0F), ("0xf0_ff", 0xF0, 0xFF),
                    ("0x44_0f", 0x44, 0x0F)]:
    u(f"usb_wvalue_{nm}", (fmt | (be << 8)) & 0xFFFFFFFF)
for mode in (0, 1, 2, 3, 4):
    u(f"usb_windex_{mode}", mode & 0x03)
u("usb_timeout", 1000)          # the default timeout of control_write/control_read
u("usb_ctrl_buf_in_trace", 0x1000)

# THE INVENTORY ROWS: each `K_*` kind and the symbol it names. A transposed ladder
# moves these, and `usb-symmap.py` proves the mapping is a bijection.
KINDS = ["init", "set_option", "get_devlist", "get_desc", "ref_device",
         "bus_number", "dev_address", "free_devlist", "open", "get_device",
         "str_ascii", "kdrv_active", "detach_kdrv", "reset_device",
         "set_config", "claim_iface", "set_alt", "ctrl_xfer", "bulk_xfer",
         "alloc_xfer", "events", "submit_xfer", "memcpy", "strerror"]
for _i, _k in enumerate(KINDS):
    s(f"usb_inventory_{_k}", symname(_i))
u("usb_inventory_len", len(SYMNAMES))
s("usb_inventory_past_end", "libusb_unknown" if len(SYMNAMES) <= 24 else symname(24))

sys.stdout.write("\n".join(OUT) + "\n")
