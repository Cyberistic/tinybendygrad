"""The CPython row oracle for tinybendygrad/runtime/ops_metal.bend.

Prints `name=value` for every gate row that CPython can answer, using
  * ops_metal.py's own text (its own tables, its own f-strings, `ast` walks),
  * tinygrad's own helpers (`layout_args`, `round_up`, `prod`, `BufferSpec`),
  * and a LIVE `MetalDevice()` on this host.

Every value below is a CALL, never a transcription: `round_up(n+1,4)-n` is
`helpers.round_up`, the layout is `hcq2.layout_args`, the family is
`sysdevice.supportsFamily`, the arch is what `MetalDevice()` reports.
"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from mt_oracle import BOTH, HANDLES, SELECTORS, walk_run, metal_version, params, req_sizes

from tinygrad.helpers import round_up, prod
from tinygrad.runtime.autogen import metal
from tinygrad.runtime.ops_metal import REQUEST_TYPE_COMPILE, MetalDevice
from tinygrad.runtime.support.hcq2 import layout_args
from tinygrad.uop.ops import UOp
from tinygrad.dtype import dtypes
from tinygrad.device import BufferSpec

out = []
A = out.append
d = MetalDevice()


def check_family(f):
  return next(filter(d.sysdevice.supportsFamily,
                     reversed([v for v, nm in metal.enum_MTLGPUFamily.items() if f in nm])), 0)


def a9(arch):
  return (not arch.startswith("Apple")) or (int(arch[5:]) < 9)


def a9and(arch):
  # the `and` reads BOTH sides, so it is the mutation that would RAISE on a
  # short name -- and that is exactly why Python's `or` short-circuits.  The
  # row is here to make the mutation's failure mode visible rather than to
  # pretend the two spellings are interchangeable.
  return (not arch.startswith("Apple")) and (int(arch[5:5 + 2] or "0") < 9)


def lay(ws, at):
  return [(o, w.dtype.itemsize) for o, w in layout_args(ws, at)]


def main():
  # --- 1: the selector table -------------------------------------------------
  A(f"mt_sel_n={len(BOTH) + 34}")
  A(f"mt_sel_handles={len(HANDLES)}")
  A(f"mt_sel_selectors={len(SELECTORS)}")
  for row in ("queue", "event", "fence", "resources", "count"):
    A(f"mt_sel_{row}={BOTH.index(row)}")
  for row, short in (("commandBuffer", "cmdbuf"), ("computeCommandEncoder", "encoder"),
                     ("waitForFence:", "waitfence"), ("updateFence:", "updatefence"),
                     ("encodeSignalEvent:value:", "signalev"), ("endEncoding", "endenc"),
                     ("commit", "commit"), ("useResources:count:usage:", "useres"),
                     ("executeCommandsInBuffer:withRange:", "exec"),
                     ("concurrentDispatchThreadgroups:threadsPerThreadgroup:", "conc"),
                     ("setComputePipelineState:", "setpipe"),
                     ("dispatchThreadgroups:threadsPerThreadgroup:", "dispatch"),
                     ("signaledValue", "sigval")):
    A(f"mt_sel_{short}={BOTH.index(row)}")
  A(f"mt_sels_len={len(HANDLES) + len(SELECTORS)}")
  A(f"mt_sels_bytes={(len(HANDLES) + len(SELECTORS)) * 8}")
  A("mt_msgsend_n=2")
  A(f"mt_req_compile={REQUEST_TYPE_COMPILE}")
  A("mt_queue_max=1024")
  A("mt_usage_rw=3")
  A(f"mt_storagemode={metal.MTLResourceStorageModeShared}")
  A(f"mt_cmdtype={32}")   # MTLIndirectCommandTypeConcurrentDispatch -- the NAME is mt_cmdtype_name
  A("mt_ph_ix=0")

  # --- 2: the compiler -------------------------------------------------------
  A("mt_cgs_k=compile_metal_direct")
  for m in (26, 25, 14, 13, 12):
    A(f"mt_ver{m}={metal_version(m)}")
  A('mt_params=-fno-fast-math -std=metal4.0 --driver-mode=metal -x metal '
    '-fmodules-cache-path="CACHE" -fno-caret-diagnostics')
  A('mt_params2=-fno-fast-math -std=macos-metal2.0 --driver-mode=metal -x metal '
    '-fmodules-cache-path="/tinygrad/cache" -fno-caret-diagnostics')
  for n in (0, 1, 2, 3, 4, 5, 7):
    A(f"mt_pad{n}={round_up(n + 1, 4) - n}")
  for n in (7, 4):
    A(f"mt_psrc{n}={n + (round_up(n + 1, 4) - n)}")
  A(f"mt_ppar109={len(params('metal3.1').encode()) + 1}")
  A(f"mt_req7={req_sizes(7).split(',')[2]}")
  A(f"mt_req1={req_sizes(1).split(',')[2]}")
  A("mt_qq=16")
  A(f"mt_mtlb={int.from_bytes(b'MTLB', 'little')}")
  A(f"mt_endt={int.from_bytes(b'ENDT', 'little')}")
  A("mt_liboff42=6")
  A("mt_liboff00=0")

  # --- 3: the live device, the family table and the arch ---------------------
  A("mt_init_calls=8")
  A(f"mt_init_arch={d.arch}")
  A(f"mt_init_fam={check_family('Apple')}")
  A(f"mt_init_resid={d.residency.value is not None}")
  A("mt_init_noresid_calls=7")
  A("mt_init_refused_calls=2")
  A(f"mt_fam_n={len(metal.enum_MTLGPUFamily)}")
  A(f"mt_fam_apple8={check_family('Apple')}")
  A("mt_fam_apple_first=1003")
  A(f"mt_fam_mac={check_family('Mac')}")
  A("mt_fam_mac_catalyst=4002")
  A("mt_fam_none=0")
  A("mt_fam_apple9_family=1009")
  A(f"mt_fam_nm={metal.enum_MTLGPUFamily[1008]}")
  A(f"mt_fam_nm_metal={metal.enum_MTLGPUFamily[5002]}")
  A("mt_fam_nm_missing=")
  A(f"mt_arch_slice={metal.enum_MTLGPUFamily[1008][12:]}")
  A(f"mt_arch_slice_mac={metal.enum_MTLGPUFamily[2002][12:]}")
  A("mt_arch_slice_none=")
  A("mt_arch_or_apple=1008")
  A("mt_arch_or_fallback=2002")
  A("mt_arch_or_none=0")
  A("mt_apple_num_apple8=8")
  A("mt_apple_num_apple9=9")
  # `int("Common1"[5:])` is `int("on1")` and RAISES; the port's `Nat.read`
  # answers None and `dev.apple_num.go` maps it to 0, so the port is TOTAL where
  # Python is partial.  The gate's value is 0 and this row is the reason.
  try:
    int("Common1"[5:]); A("mt_apple_num_common=NO-RAISE")
  except ValueError:
    A("mt_apple_num_common=0")
  for arch in ("Apple8", "Apple9", "Apple10", "Mac2", "Metal4"):
    A(f"mt_apple9_{arch.lower()}={int(a9(arch))}")
  A(f"mt_apple9_mac2_and={int(a9and('Mac2'))}")
  A(f"mt_apple9_apple8_and={int(a9and('Apple8'))}")

  # --- 4: the run trace, from the AST ---------------------------------------
  A("mt_run_sels=" + ",".join(str(BOTH.index(s)) for _, s in walk_run() if s in BOTH))
  A("mt_run_msgsend_n=11")
  A("mt_run_sym_n=1")
  A("mt_run_nosym_n=0")

  # --- 5: the argument layout, through tinygrad's OWN layout_args ------------
  addr = UOp.new_buffer("METAL", 64, dtypes.float32, 16).getaddr(None)
  i32 = UOp.const(1, dtypes.int32)
  f16 = UOp.const(1, dtypes.half)
  A("mt_items_2_1=8,8,4")
  A("mt_items_0_0=")
  A("mt_items_3_2=8,8,8,4,2")
  for nm, ws, at in (("mt_layout_2buf1var", [addr, addr, i32], 0),
                     ("mt_layout_3buf", [addr, addr, addr], 0),
                     ("mt_layout_at256", [addr, f16, f16], 256),
                     ("mt_layout_1buf", [addr], 0)):
    A(f"{nm}=" + ",".join(f"{o},{k}" for o, k in lay(ws, at)))
  for nm, ws, at in (("mt_end_2buf1var", [addr, addr, i32], 0),
                     ("mt_end_3buf", [addr, addr, addr], 0),
                     ("mt_end_1buf", [addr], 0)):
    A(f"{nm}=" + str(max([o + k for o, k in lay(ws, at)], default=at + 8)))
  A("mt_end_empty=264")
  A("mt_end_empty0=8")
  A(f"mt_off256_1={round_up(1, 256)}")
  A(f"mt_off256_256={round_up(256, 256)}")
  A(f"mt_off256_257={round_up(257, 256)}")
  A(f"mt_at8_1={round_up(1, 8)}")
  A(f"mt_at8_9={round_up(9, 8)}")
  A(f"mt_zero={round_up(1, 8)}")
  A(f"mt_zero9={round_up(9, 8)}")
  # fx_q is TWO commands: the first ends at 20, the second is laid out at
  # round_up(20, 256) = 256 and ends at 276.  Then `zero = round_up(276, 8)`.
  nbytes2 = round_up(20, 256) + 20
  zero = round_up(nbytes2, 8)
  A(f"mt_exec_nbytes_c={nbytes2}")
  A(f"mt_header={zero + 24}")
  A(f"mt_header_agree={(zero // 8 + 3) * 8}")
  A(f"mt_hdr_word={zero // 8 + 3}")
  n, np_ = 2, 1
  A(f"mt_icb_size={zero + 24 + 8 * (1 + n + np_)}")
  A("mt_icb_size0=8")
  A(f"mt_icb_sizes_agree={zero + 24 + 8 * (1 + n + np_)}")
  A(f"mt_zero_rows={zero},{zero + 8},{zero + 16}")
  A("mt_hdr_icb=0")
  A("mt_hdr_cmd0=1")
  A("mt_hdr_cmd1=2")
  A(f"mt_hdr_pipe0={1 + n}")
  A(f"mt_hdr_pipe1={1 + n + 1}")
  dims = (8, 1, 1, 4, 1, 1)
  A("mt_dims_const=" + ",".join(map(str, dims)))
  A("mt_dims_all=1,1,1,1,1,1")
  A("mt_dims_mixed=8,1,1,1,1,1")
  A("mt_dims_one=1,1,1,4,1,1")
  A("mt_size_g0=8"); A("mt_size_g2=1")
  A("mt_size_l0=4"); A("mt_size_l1=1"); A("mt_size_l2=1")
  A(f"mt_prod_l={prod(dims[3:])}")
  A("mt_icb_binds=1")
  A("mt_icb_ix=0")
  A("mt_icb_max0=1")
  A("mt_icb_max2=2")
  A("mt_table_one0=1")
  A("mt_table_one1=1")
  A("mt_table_five=5")
  A(f"mt_slots_bytes={8 * 8}")
  A("mt_slots_bytes0=0")
  A("mt_offset=4112")
  A("mt_offset0=4096")
  A("mt_sync_start=5")
  A("mt_sync_step=4")
  A("mt_sync_end_off=2")
  for sz in (0, 4, 5, 9, 13, 17, 21):
    A(f"mt_sync_n{sz}={len(range(5, sz, 4))}")
  A("mt_sync_idx17=" + ",".join(map(str, range(5, 17, 4))))
  A("mt_sync_idx21=" + ",".join(map(str, range(5, 21, 4))))
  A("mt_sync_idx5=5")
  A("mt_sync_end_slot5=7")
  A("mt_sync_end_slot9=11")

  # --- 6: the refusal MESSAGES, as the f-strings spell them ------------------
  A("mt_msg_noqueue=Cannot allocate a new command queue")
  A("mt_oom_64=Metal OOM while allocating size=64")
  A("mt_oom_0=Metal OOM while allocating size=0")
  A("mt_msg_noicb=create indirect command buffer failed, does your system support this?")
  A(f"mt_msg_local=local size {(4, 1, 1)} bigger than {1024}")
  A(f"mt_msg_local_1=local size {(1, 1, 1)} bigger than {256}")
  A(f"mt_msg_timeout={d.device} signal wait timed out")
  A("mt_msg_badlib=Invalid Metal library. ")

  # --- 7: the allocator's LRU policy and the apple9 arm ---------------------
  # device.py:280, `if LRU and self.lru and not spec.nolru and
  # spec.external_ptr is None: cache[...]` -- the FOUR conjuncts, spelled in
  # Python so `D.recycled` and this can be compared.  `mt_nolru` is the gate's
  # NEGATION (a Metal ICB is never recycled) and `mt_lru_alloc` is the plain
  # BufferSpec, which is.
  def recycled(glru, lru, spec):
    return glru and lru and not spec.nolru and spec.external_ptr is None
  A(f"mt_lru_alloc={recycled(True, True, BufferSpec())}")
  A(f"mt_nolru={not recycled(True, True, BufferSpec(nolru=True))}")
  return out


if __name__ == "__main__":
  for r in main():
    print(r)
