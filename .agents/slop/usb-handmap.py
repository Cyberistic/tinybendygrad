#!/usr/bin/env python3
"""THE HAND MAP: port constant -> an AST POSITION in tinygrad/runtime/support/usb.py.

A hand map of VALUES is how ops_nv shipped 33 wrong constants and ops_rdma
shipped `BNXT_VENDOR` 5356 for 5348: re-transcribing a literal is exactly where
the error enters, and this file's own differ caught two of mine that way
(`SENTINEL_MAGIC` 1363148800 for 0x51000000, `FAST_P1_MASK` 215 for
0b11011111 == 223). So the map is a map of POSITIONS -- `(line, col)` -- and the
VALUE is whatever the AST node at that position evaluates to. A wrong value is
then not expressible; a wrong position is, and a wrong position is loud, because
every constant that shared the position moves with it.

Positions are 1-based line, 0-based column. `--list` prints every evaluable
integer node on a line so a position can be checked by eye without running
anything; the map below was built from that listing.
"""
import ast
import io
import sys

SRC = "tinygrad/runtime/support/usb.py"
LINES = io.open(SRC).read().split("\n")
TREE = ast.parse("\n".join(LINES))


# the module-level names `usb.py:208-212` binds, so an expression that READS them
# evaluates instead of being reported unresolvable.
ENV = {"HALF": 0x40000, "CHUNK": 0x40000 - 512, "SLOT": 0x4000,
       "USB_MAX_STREAM": 1 << 20, "USB_HOST_SIZE": 32 + 2 * 0x40000 + (1 << 20)}


def ev(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, str)):
        return node.value
    if isinstance(node, ast.Name) and node.id in ENV:
        return ENV[node.id]
    if isinstance(node, ast.Tuple):
        vals = [ev(e) for e in node.elts]
        return tuple(vals) if all(v is not None for v in vals) else None
    if isinstance(node, ast.BinOp):
        a, b = ev(node.left), ev(node.right)
        if a is None or b is None:
            return None
        for t, f in ((ast.Add, lambda x, y: x + y), (ast.Sub, lambda x, y: x - y),
                     (ast.Mult, lambda x, y: x * y), (ast.LShift, lambda x, y: x << y)):
            if isinstance(node.op, t):
                return f(a, b)
    return None


# COMPOUND BEFORE BARE. `HALF, CHUNK, SLOT = 0x40000, 0x40000 - 512, 0x4000` puts a
# Tuple, a BinOp and a Constant at the SAME column, and `USB_HOST_SIZE = 32 + 2 *
# HALF + USB_MAX_STREAM` puts a BinOp and the literal `32` at the same column. The
# interesting node is the one that CONSUMES the others, so BinOp wins over
# Constant and Constant wins over Tuple.
_RANK = {ast.BinOp: 0, ast.UnaryOp: 0, ast.Constant: 1, ast.Tuple: 2, ast.Name: 3}


def at(ln, col):
    best = None
    for node in ast.walk(TREE):
        if getattr(node, "lineno", None) != ln or getattr(node, "col_offset", None) != col:
            continue
        v = ev(node)
        if v is None:
            continue
        r = _RANK.get(type(node), 9)
        if best is None or r < best[0]:
            best = (r, v)
    if best is None:
        raise KeyError(f"no evaluable node at {SRC}:{ln}:{col}")
    return best[1]


# name -> (line, col), and the source text at that position for the audit trail.
MAP = {
    # :208 `HALF, CHUNK, SLOT = 0x40000, 0x40000 - 512, 0x4000`
    "usb_half": (208, 20), "usb_chunk": (208, 29), "usb_slot": (208, 44),
    "usb_sentinel_block": (208, 39),
    # :210 `USB_MAX_STREAM = 1 << 20`; :212 `32 + 2 * HALF + USB_MAX_STREAM`
    "usb_max_stream": (210, 17), "usb_host_size_lo32": (212, 16),
    # :214 `usb_host(dev)[:24]`; :215 `usb_host(dev)[32 : 32 + 2 * HALF]`
    "usb_link_bytes": (214, 48), "usb_stage_lo": (215, 48), "usb_stage_2half": (215, 56),
    # :221 `(2,), dtypes.uint32`; :222 `[:1]`; :223 `[1:]`
    "usb_vram_words": (221, 50), "usb_go_word_stop": (222, 46), "usb_scratch_word": (223, 50),
    # :226 `(0x85000,)`; :227 `[0x800:0x804]`; :228 `[0x100c:0x1010]`;
    # :229 `[0x5000 : 0x5000 + 2 * HALF]`
    "usb_asm24_size": (226, 51), "usb_win_fence_lo": (227, 49), "usb_win_fence_hi": (227, 55),
    "usb_win_cq_lo": (228, 46), "usb_win_cq_hi": (228, 53), "usb_win_sram_lo": (229, 48),
    # :41 `alloc_cbuffer(4 << 20)`; :42 `alloc_cbuffer(0x1000)`
    "usb_bulk_buf": (41, 50), "usb_ctrl_buf": (42, 50),
    # :321 `(16 * (k + r), ...)` and `(16 * (k + r) + 8, ...)`
    "usb_table_row_bytes": (321, 16), "usb_table_size_off": (321, 88),
    # :104 `0xF3`; :107 `0xF0` / `mode & 0x03`; :173 `0xF2`; :163 `0xE4`; :168 `0xE5`
    "usb_req_power": (104, 84), "usb_req_f0": (107, 27), "usb_mode_mask": (107, 67),
    "usb_req_f2": (173, 27), "usb_req_e4": (163, 38), "usb_req_e5": (168, 60),
    # :139 `(0x44 if value is not None else 0x4) | int(bus > 0)`
    "usb_cfg_fmt_wr": (139, 16), "usb_cfg_fmt_rd": (139, 47),
    # :140 `(bus << 24) | (dev << 19) | (fn << 16) | (byte_addr & 0xfff)`
    "usb_cfg_bus_shift": (140, 22), "usb_cfg_dev_shift": (140, 36),
    "usb_cfg_fn_shift": (140, 49), "usb_cfg_ba_mask": (140, 68),
    # :149 `0x60`, `0x0F`, `mode=1`; :155 `0x20`, `0x0F`, `mode=2`
    "usb_stream_fmt_wr": (149, 19), "usb_stream_byte_en": (149, 25),
    "usb_stream_fmt_rd": (155, 17), "usb_stream_byte_en_rd": (155, 23),
    # :161 `range(0, length, 0xFF)`
    "usb_xdata_chunk": (161, 32),
    # :172 `round_up(len(buf), 512)`; :173 `// 512` and `ceildiv(..., 0x4000)`
    "usb_sram_align": (172, 53), "usb_sram_align2": (173, 58), "usb_sram_slot": (173, 117),
    # :173 `(slot_start & 0xFF) | (...) << 8`
    "usb_scsi_slot_mask": (173, 83), "usb_scsi_slot_shift": (173, 128),
    # :254 `(g & 0xFFFFFF) | 0x51000000`
    "usb_sentinel_mask": (254, 45), "usb_sentinel_magic": (254, 57),
    # :122 `(fmt_type & 0b11011111) == 0b01000000) or ((fmt_type & 0b10111000) == 0b00110000)`
    "usb_fast_p1_mask": (122, 20), "usb_fast_p1_val": (122, 35),
    "usb_fast_p2_mask": (122, 63), "usb_fast_p2_val": (122, 78),
    # :334 `(((need - fence.cast(dtypes.uint64)) & 0xff) > 1)`
    "usb_drain_mod": (334, 82), "usb_drain_gt": (334, 90),
    # :375 `(size + (second > 0).where(UOp.const(512, ...), ...) + 511) // 512 * 512`
    "usb_copyout_sentinel": (375, 46), "usb_copyout_r1": (375, 92), "usb_copyout_r2": (375, 100),
    # :387 `str(p.tag).startswith(("usb_host", "usb_xfer", "put_value", "cmdbuf_copy"))`
    "usb_remote_tuple": (387, 97),
    # :89 `struct.pack("<IIIBBB16s", 0x43425355, tag, ...)`, :91 `"<IIIB"`
    "usb_cdb_magic_usbc": (89, 48),
    # :35 the enumeration label, :50 the string buffer, :65/:67 the rtypes
    "usb_string_buf": (50, 97), "usb_ctrl_rtype_out": (67, 64), "usb_ctrl_rtype_in": (71, 64),
    # :77-78 / :83 the bulk endpoints
    "usb_ep_out": (78, 20), "usb_ep_in": (83, 77),
    # :60-62 the configuration and interface numbers
    "usb_setcfg_n": (60, 58), "usb_claim_iface": (61, 56), "usb_alt_setting": (62, 66),
    "usb_alt_setting2": (62, 69),
    # :92 the reply magic of `send_batch`
    "usb_reply_magic_usbs": (92, 37),
    # :25 the log LEVEL (the option is `LIBUSB_OPTION_LOG_LEVEL`, read from the
    # module) and :132 the three status-map KEYS -- and note the dict declares them
    # 1, 4, 2, so the port's CPL_UNSUP < CPL_ABORT < CPL_RETRY is a DECLARATION
    # order and not a value order.
    "usb3_log_level_debug": (25, 90),
    "usb_cpl_unsup": (132, 20), "usb_cpl_abort": (132, 65), "usb_cpl_retry": (132, 91),
    # :91 the reply read length and timeout
    "usb_reply_len": (91, 67), "usb_reply_timeout": (91, 79),
}

# A SLICE STOP IS AN EXCLUSIVE BOUND, and one of these is not the value the port
# stores. `usb_go = usb_vram(dev)[:1]` is the FIRST word: the source's stop is 1
# and the word index is 0. Recorded as a transform rather than as a value, so the
# one-step relation is visible instead of being a hand-typed correction.
DERIVED = {"usb_go_word": ("usb_go_word_stop", lambda v: v - 1)}

if __name__ == "__main__":
    if "--list" in sys.argv:
        for ln in (41, 42, 50, 60, 61, 62, 67, 71, 77, 78, 79, 83, 89, 91, 92, 104, 107, 122,
                   139, 140, 149, 155, 161, 163, 168, 172, 173, 208, 210, 212, 214, 215, 221,
                   222, 223, 226, 227, 228, 229, 254, 321, 334, 375, 387):
            got = []
            for n in ast.walk(TREE):
                if getattr(n, "lineno", None) == ln:
                    v = ev(n)
                    if v is not None:
                        got.append((getattr(n, "col_offset", -1), v))
            print(f"{ln:4d} {LINES[ln - 1].strip()[:78]}")
            for c, v in sorted(set(got)):
                print(f"       col {c:4d} = {v!r}")
        sys.exit(0)
    bad = 0
    allmap = dict(MAP)
    allmap.update({k: MAP[src] for k, (src, _) in DERIVED.items()})
    for nm, pos in sorted(allmap.items()):
        try:
            v = at(*pos)
            if nm in DERIVED:
                v = DERIVED[nm][1](v)
            print(f"{nm}={v!r}")
        except KeyError as e:
            print(f"UNRESOLVED {nm} {e}")
            bad += 1
    print(f"# hand map: {len(MAP)} positions, {bad} unresolved", file=sys.stderr)
    sys.exit(1 if bad else 0)