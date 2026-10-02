#!/usr/bin/env python3
"""Drive the REAL `MetalCompiler.compile` on this host and measure everything the
port would need: the request the port builds, and the reply the CALLBACK sees.
The callback is INSTRUMENTED, because `reply[8:16]` is only meaningful on the
pre-slice blob -- reading it on the post-slice answer is how you get a 2 GB header."""
import platform, struct, sys, ctypes
import tinygrad.runtime.support.objc as objc
from tinygrad.runtime.ops_metal import MetalCompiler, REQUEST_TYPE_COMPILE
from tinygrad.helpers import round_up, cache_dir, to_mv
from tinygrad.device import CompileError

src = sys.stdin.read()
macos_major = int(platform.mac_ver()[0].split('.')[0])
metal_version = ("metal4.0" if macos_major >= 26 else "metal3.1" if macos_major >= 14
                 else "metal3.0" if macos_major >= 13 else "macos-metal2.0")
params = (f'-fno-fast-math -std={metal_version} --driver-mode=metal -x metal '
          f'-fmodules-cache-path="{cache_dir}" -fno-caret-diagnostics')
src_padded = src.encode() + b'\x00' * (round_up(len(src) + 1, 4) - len(src))
params_padded = params.encode() + b'\x00'
request = struct.pack('<QQ', len(src_padded), len(params_padded)) + src_padded + params_padded
print("mac_ver        =", platform.mac_ver()[0])
print("macos_major    =", macos_major)
print("metal_version  =", metal_version)
print("len(src)       =", len(src), " len(src_padded) =", len(src_padded))
print("len(params_pad)=", len(params_padded), " len(request) =", len(request))
print("request <QQ>   =", struct.unpack('<QQ', request[:16]))

seen = {}
c = MetalCompiler()
@ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_int32, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_char_p)
def cb(blockptr, error, dataPtr, dataLen, errorMessage):
  seen["error"] = error
  seen["dataLen"] = dataLen
  seen["errMsg"] = errorMessage
  if error == 0:
    reply = bytes(to_mv(dataPtr, dataLen))
    seen["len(reply)"] = len(reply)
    seen["reply[8:16]"] = struct.unpack('<LL', reply[8:16])
    seen["hdr_sum"] = sum(struct.unpack('<LL', reply[8:16]))
    seen["reply[:4]"] = reply[:4], "reply[-4:]", reply[-4:]
    seen["ret_len"] = len(reply[seen["hdr_sum"]:])
    seen["ret_magic"] = reply[seen["hdr_sum"]:][:4], reply[seen["hdr_sum"]:][-4:]

MetalCompiler.support.MTLCodeGenServiceBuildRequest(
  c.cgs, None, REQUEST_TYPE_COMPILE, request, len(request), ctypes.byref(cb, -0x10))
for k, v in seen.items(): print(f"{k:14s} =", v)
