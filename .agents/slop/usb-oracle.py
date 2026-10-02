#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/runtime/support/usb.bend.

EVERY expectation here is produced by CALLING the real object -- getattr on
tinygrad.runtime.autogen.libusb, ctypes.sizeof, struct.calcsize, struct.pack,
int arithmetic on the SAME expression usb.py writes. Nothing is transcribed by
eye, because agent-core.md records five units where a hand-typed expectation was
wrong (ops_nv: 33 of 219 constants) and one where the PORT and the ORACLE were
wrong in the SAME WAY (nv_query_litter), so their agreement meant nothing.

PORT_INTERNAL rows are facts about the Bend port, not about libusb. They are
listed in one block so the report can say exactly which rows CPython does and
does not corroborate.
"""
import ctypes
import struct
import sys

sys.path.insert(0, ".")
from tinygrad.runtime.autogen import libusb  # noqa: E402

OUT = []


def u(nm, v):
    OUT.append(f"{nm}={v}")


def i(nm, v):
    OUT.append(f"{nm}={v}")


def s(nm, v):
    OUT.append(f"{nm}={v}")


NOT_FOUND = 4294967295


def u32_to_i32(x: int) -> int:
    """The Bend port stores a C enum in a U32 bit pattern; CPython's dict keys
    are signed. This is the same conversion `show_i32` does in the port."""
    return x - (1 << 32) if x >= (1 << 31) else x

# ---------------------------------------------------------------------------
# THE libusb ENUM TABLES. `usb.py` reaches these only through named constants
# (LIBUSB_OPTION_LOG_LEVEL, LIBUSB_ERROR_INTERRUPTED, LIBUSB_TRANSFER_TYPE_BULK),
# but the dict IS the descriptor table and both directions are what the port
# rows, so both are compared.
# ---------------------------------------------------------------------------
# tag -> the attribute name in autogen/libusb.py
TAGS = {
    "classcode": "enum_libusb_class_code",
    "dtype": "enum_libusb_descriptor_type",
    "epdir": "enum_libusb_endpoint_direction",
    "eptype": "enum_libusb_endpoint_transfer_type",
    "xtype": "enum_libusb_transfer_type",
    "xstatus": "enum_libusb_transfer_status",
    "xflags": "enum_libusb_transfer_flags",
    "err": "enum_libusb_error",
    "reqtype": "enum_libusb_request_type",
    "streq": "enum_libusb_standard_request",
    "recip": "enum_libusb_request_recipient",
    "speed": "enum_libusb_speed",
    "supspeed": "enum_libusb_supported_speed",
    "loglevel": "enum_libusb_log_level",
    "logcb": "enum_libusb_log_cb_mode",
    "option": "enum_libusb_option",
    "isosync": "enum_libusb_iso_sync_type",
    "isousage": "enum_libusb_iso_usage_type",
    "cap": "enum_libusb_capability",
    "bostype": "enum_libusb_bos_type",
    "ext20": "enum_libusb_usb_2_0_extension_attributes",
    "sscap": "enum_libusb_ss_usb_device_capability_attributes",
}

for tag, attr in TAGS.items():
    tbl = getattr(libusb, attr)
    if tag == "classcode":
        pass
    # name -> value, for EVERY entry, in the dict's own insertion order.
    for val, name in tbl.items():
        i(f"usb_{tag}_v_{name}", val)
    # value -> name, ONE ROW PER ENTRY, and this is where the collision shows:
    # dict.items() yields (KEY, VALUE) with the int FIRST, so the pair reads the
    # other way round from how it is written. `tbl[val]` for LIBUSB_CLASS_IMAGE
    # is LIBUSB_CLASS_PTP, and that row sitting next to PTP's own IS the negative
    # case -- a name whose value->name answer is not itself.
    for val, name in tbl.items():
        s(f"usb_{tag}_n_{name}", tbl[val])

# the four constants usb.py NAMES, by getattr
i("usb_err_interrupted_signed", getattr(libusb, "LIBUSB_ERROR_INTERRUPTED"))
i("usb_err_other_signed", getattr(libusb, "LIBUSB_ERROR_OTHER"))
i("usb_err_success_signed", getattr(libusb, "LIBUSB_SUCCESS"))
u("usb_opt_log_level", getattr(libusb, "LIBUSB_OPTION_LOG_LEVEL"))
u("usb_opt_log_level_is_debug", getattr(libusb, "LIBUSB_LOG_LEVEL_DEBUG"))
u("usb_opt_max", getattr(libusb, "LIBUSB_OPTION_MAX"))
s("usb_classcode_6_name", libusb.enum_libusb_class_code[6])
u("usb_classcode_len", len(libusb.enum_libusb_class_code))
u("usb_classcode_image_walrus", getattr(libusb, "LIBUSB_CLASS_IMAGE"))
u("usb_classcode_image_in_dict", int("LIBUSB_CLASS_IMAGE" in libusb.enum_libusb_class_code))
u("usb_classcode_ptp_walrus", getattr(libusb, "LIBUSB_CLASS_PTP"))

# THE LAST-WINS FIXTURE, as a REAL dict: a repeated KEY is overwritten by the
# later literal, which is exactly what `dict[int, str]` did to
# `LIBUSB_CLASS_IMAGE`, and the NAME side is exercised by two entries carrying the
# same string.
SYNTH = {}
for _v, _n in ((10, "SYNTH_ALPHA"), (11, "SYNTH_BETA"), (10, "SYNTH_GAMMA"),
               (12, "SYNTH_BETA"), (13, "SYNTH_DELTA")):
    SYNTH[_v] = _n
s("usb_synth_n_10", SYNTH[10])
s("usb_synth_n_11", SYNTH[11])
s("usb_synth_n_13", SYNTH[13])
_byname = {}
for _v, _n in ((10, "SYNTH_ALPHA"), (11, "SYNTH_BETA"), (10, "SYNTH_GAMMA"),
               (12, "SYNTH_BETA"), (13, "SYNTH_DELTA")):
    _byname[_n] = _v          # a repeated NAME, LAST wins
u("usb_synth_v_alpha", _byname["SYNTH_ALPHA"])
u("usb_synth_v_gamma", _byname["SYNTH_GAMMA"])
u("usb_synth_v_beta", _byname["SYNTH_BETA"])
u("usb_synth_v_absent", NOT_FOUND)

# PORT_INTERNAL: the two "absent" rows. CPython has no name for them; what is
# being asserted is that the port answers NOT_FOUND and NOT 0.
u("usb_enumval_notfound_is_io", NOT_FOUND)
# QUERIED, not asserted: 4294967295 is LIBUSB_ERROR_IO's bit pattern so it IS in
# the table, and 4242 is in nothing.
s("usb_enumnm_absent_4242", libusb.enum_libusb_class_code.get(4242, "LIBUSB_ENUM_NONE"))
# 4294967295 is a U32 BIT PATTERN and the dict's keys are SIGNED ints, so the
# query has to be made with the same conversion the port's table stores: -1.
s("usb_enumnm_absent_neg1", libusb.enum_libusb_error.get(u32_to_i32(4294967295), "LIBUSB_ENUM_NONE"))

# ---------------------------------------------------------------------------
# THE STRUCT FIELD LISTS, BY NAME AND IN ORDER. `__annotations__` is the
# declaration order; `register_fields` in the source is the same order, and
# C-ASSERT checks the two agree before either is trusted.
# ---------------------------------------------------------------------------
STRUCTS = [
    ("transfer", "struct_libusb_transfer"),
    ("device_descriptor", "struct_libusb_device_descriptor"),
    ("endpoint_descriptor", "struct_libusb_endpoint_descriptor"),
    ("interface_descriptor", "struct_libusb_interface_descriptor"),
    ("config_descriptor", "struct_libusb_config_descriptor"),
    ("interface", "struct_libusb_interface"),
    ("interface_association_descriptor", "struct_libusb_interface_association_descriptor"),
    ("interface_association_descriptor_array", "struct_libusb_interface_association_descriptor_array"),
    ("control_setup", "struct_libusb_control_setup"),
    ("iso_packet_descriptor", "struct_libusb_iso_packet_descriptor"),
    ("bos_descriptor", "struct_libusb_bos_descriptor"),
    ("bos_dev_capability_descriptor", "struct_libusb_bos_dev_capability_descriptor"),
    ("ss_usb_device_capability_descriptor", "struct_libusb_ss_usb_device_capability_descriptor"),
    ("ss_endpoint_companion_descriptor", "struct_libusb_ss_endpoint_companion_descriptor"),
    ("usb_2_0_extension_descriptor", "struct_libusb_usb_2_0_extension_descriptor"),
    ("container_id_descriptor", "struct_libusb_container_id_descriptor"),
    ("platform_descriptor", "struct_libusb_platform_descriptor"),
    ("init_option", "struct_libusb_init_option"),
    ("init_option_value", "struct_libusb_init_option_value"),
    ("pollfd", "struct_libusb_pollfd"),
    ("version", "struct_libusb_version"),
    ("timeval", "struct_timeval"),
]

FIELDS = {}
for tag, sname in STRUCTS:
    st = getattr(libusb, sname)
    names = list(st.__annotations__.keys())
    FIELDS[tag] = names
    s(f"usb_fld_{tag}", " ".join(names))
    # :218 makes sizeof an ELEMENT COUNT, so it is arithmetic and not a comment.
    u(f"usb_siz_{tag}", ctypes.sizeof(st))

# the SEVEN names usb.py addresses or reads, and their ORDINALS
for nm in ("status", "length", "buffer", "endpoint", "type", "timeout", "actual_length"):
    u(f"usb_fld_transfer_{nm}_ix", FIELDS["transfer"].index(nm) if nm in FIELDS["transfer"] else NOT_FOUND)
u("usb_fld_transfer_nosuch_ix", NOT_FOUND)
for nm in ("idVendor", "idProduct", "iProduct", "iManufacturer"):
    u(f"usb_fld_device_descriptor_{nm}_ix", FIELDS["device_descriptor"].index(nm))
for ix in (5, 11, 99):
    fl = FIELDS["transfer"]
    s(f"usb_fld_transfer_at{ix}", fl[ix] if ix < len(fl) else "")

sys.stdout.write("\n".join(OUT) + "\n")