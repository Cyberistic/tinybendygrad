#!/usr/bin/env python3
"""THE SEAM ORACLE: run the REAL `MetalCompiler.compile` on this host and emit the
rows the port's `t_seam` section prints.

Nothing here is transcribed. Every number is produced by calling
`MTLCodeGenServiceBuildRequest` through Apple's block ABI with an INSTRUMENTED
callback -- the same call `ops_metal.py:68` makes -- and reading what came back.

THE TWO THINGS ONLY A REAL CALL ANSWERS, and both were un-gated until now:

  1. `reply[8:16]` is `(104, 0)` here, so `:50`'s
     `ret = reply[sum(struct.unpack('<LL', reply[8:16])):]` slices at byte 104 of a
     4580-byte reply. The port had `mt_liboff42` and `mt_liboff00` -- two synthetic
     fixtures -- and no row that could be wrong about a real header.
  2. THE TWO BLOBS ARE DIFFERENT. The UNSLICED reply starts with `b'\\x03\\x00\\x00\\x00'`,
     a little-endian 3, and only the SLICED `ret` carries `MTLB`. Reading the magic
     off the wrong blob is off by 1112298570 and still LOOKS like a magic, which is
     the `nv_query_litter` failure mode exactly: a port and an oracle agreeing on a
     number neither of them read off the thing.

THE COMPILER ERRORS TOO, and that is worth having: a bad kernel answers
`error == 2` with a NUL-terminated `errorMessage`, so `:47`'s `if error == 0` is a
comparison against two values this host actually produced.

Run with `.venv/bin/python` (bend2-constraints.md line 1733: NOT `python3`).
"""
import ctypes, platform, struct, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tinygrad.runtime.ops_metal import MetalCompiler, REQUEST_TYPE_COMPILE
from tinygrad.helpers import round_up, cache_dir, to_mv

# TWO fixed sources, one that compiles and one that cannot. Their LENGTHS are what
# the gate's `mt_psrc*` / `mt_req*` row names carry, so editing either changes the
# row names and `mt_diff.py` reports ORACLE-ONLY rather than passing quietly.
GOOD = """#include <metal_stdlib>
using namespace metal;
typedef struct { device float *a; int n; } args_t;
kernel void kern(constant args_t &args [[buffer(0)]], uint3 g [[thread_position_in_grid]]) {
  args.a[g.x] = args.a[g.x] + float(args.n);
}
"""
BAD = """#include <metal_stdlib>
using namespace metal;
kernel void kern(uint args [[buffer(0)]]) {
}
"""


def request_for(src):
  macos_major = int(platform.mac_ver()[0].split('.')[0])
  metal_version = ("metal4.0" if macos_major >= 26 else "metal3.1" if macos_major >= 14
                   else "metal3.0" if macos_major >= 13 else "macos-metal2.0")
  params = (f'-fno-fast-math -std={metal_version} --driver-mode=metal -x metal '
            f'-fmodules-cache-path="{cache_dir}" -fno-caret-diagnostics')
  src_padded = src.encode() + b'\x00' * (round_up(len(src) + 1, 4) - len(src))
  params_padded = params.encode() + b'\x00'
  return (macos_major, metal_version, len(params), src_padded, params_padded,
          struct.pack('<QQ', len(src_padded), len(params_padded)) + src_padded + params_padded)


def fire(cgs, request, sink):
  @ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_int32, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_char_p)
  def cb(_blockptr, error, dataPtr, dataLen, errorMessage):
    sink["error"] = error
    sink["dataLen"] = dataLen
    sink["msg"] = errorMessage
    if error == 0:
      reply = bytes(to_mv(dataPtr, dataLen))
      hdr, warn = struct.unpack('<LL', reply[8:16])
      sink["reply_len"] = len(reply)
      sink["lead"] = int.from_bytes(reply[:4], "little")
      sink["hdr"], sink["warn"] = hdr, warn
      sink["ret"] = reply[hdr + warn:]
  MetalCompiler.support.MTLCodeGenServiceBuildRequest(
    cgs.cgs, None, REQUEST_TYPE_COMPILE, request, len(request), ctypes.byref(cb, -0x10))


def main():
  cgs = MetalCompiler()
  out = {}
  major, mv, nparams, sp, pp, req = request_for(GOOD)
  good = {}
  fire(cgs, req, good)
  bad = {}
  _, _, _, _, _, badreq = request_for(BAD)
  fire(cgs, badreq, bad)

  ret = good["ret"]
  print(f"mt_macos_major={major}")
  print(f"mt_ver_host={mv}")
  print(f"mt_psrc{len(GOOD)}={len(sp)}")
  print(f"mt_ppar{nparams}={len(pp)}")
  print(f"mt_req{len(GOOD)}={len(req)}")
  print(f"mt_reply_hdr={good['hdr']}")
  print(f"mt_reply_warn={good['warn']}")
  print(f"mt_liboff_host={good['hdr'] + good['warn']}")
  print(f"mt_reply_lead={good['lead']}")
  print(f"mt_err_ok={good['error']}")
  print(f"mt_err_compile={bad['error']}")
  print(f"mt_cb_ok0={'True' if good['error'] == 0 else 'False'}")
  print(f"mt_cb_bad2={'True' if bad['error'] == 0 else 'False'}")
  print(f"mt_mtlb_ret={int.from_bytes(ret[:4], 'little')}")
  print(f"mt_endt_ret={int.from_bytes(ret[-4:], 'little')}")
  print(f"mt_ret_bytes={len(ret)}")
  # The two things that must NEVER be confused, printed as data so a diff catches it.
  print(f"mt_reply_is_mtlb={'True' if good['lead'] == int.from_bytes(b'MTLB', 'little') else 'False'}")
  print(f"mt_ret_is_mtlb={'True' if ret[:4] == b'MTLB' else 'False'}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
