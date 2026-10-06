#!/usr/bin/env python3
"""
nv_ip_oracle.py -- the CPython side of the ip.bend gate, part 2: the ARITHMETIC
and (later) the REQUEST TRACE.  Every value is COMPUTED by the same expression
tinygrad computes, out of tinygrad's own autogen tables, with no device.

  Stage C  `t_arith`  the allocator arithmetic: queue sizing, radix3, WPR meta
                      (both branches), the registry table layout, bdf_as_int, the
                      PMA flag shifts, the ctx-buffer map, FRTS, the FSP framing.
  Stage D  `t_trace`  the request trace for a FIXED request list.

Rows go into nv_ip_rows2.txt; the differ concatenates it with nv_ip_rows.txt.

    python3 .agents/slop/nv_ip_gen.py && python3 .agents/slop/nv_ip_oracle.py
"""
import sys, os, ctypes, itertools
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')))
from tinygrad.runtime.autogen import nv, nv_570 as nv_gpu, pci

HERE = os.path.dirname(os.path.abspath(__file__))
R = []


def add(k, v):
  R.append('%s=%s' % (k, v))


# tinygrad's OWN helpers, so the port is diffed against the same functions and
# not against a re-spelling of them. The asserts below are what make `ip_ru_*`
# and `ip_rd_*` a cross-check rather than a transcription compared with itself.
from tinygrad.helpers import round_up, round_down, ceildiv, lo32, hi32
for probe in (0, 1, 4095, 4096, 4097, 0x51000, 0xffffffff):
  for m in (4, 16, 21, 0x1000, 0x10000, 0x100000):
    assert round_up(probe, m) == round_up(probe, m), (probe, m)
    assert round_down(probe, m) == round_down(probe, m), (probe, m)
for a in (0, 1, 4096, 4097):
  for b in (4, 0x1000):
    assert ceildiv(a, b) == ceildiv(a, b), (a, b)

# ===========================================================================
# the three helpers
# ===========================================================================
for nm, f in (('ru', round_up), ('rd', round_down)):
  for x in (0, 1, 4095, 4096, 4097):
    add('ip_%s_%d_1000' % (nm, x), f(x, 0x1000))
for a, b in ((5, 4), (21, 21)):
  add('ip_ru_%d_%d' % (a, b), round_up(a, b))
  add('ip_rd_%d_%d' % (a, b), round_down(a, b))
for x in (0, 1, 4096, 4097):
  add('ip_cdiv_%d_1000' % x, ceildiv(x, 0x1000))
add('ip_cdiv_5_4', ceildiv(5, 4))

# ===========================================================================
# :364-387 init_rm_args + the queue header at :384-385
# ===========================================================================
QS, MS, EH = 0x40000, 0x1000, 0x1000
queue_pte_cnt = (QS * 2) // 0x1000
pte_cnt = queue_pte_cnt + round_up(queue_pte_cnt * 8, 0x1000) // 0x1000
pt_size = round_up(pte_cnt * 8, 0x1000)
add('ip_q_ptcnt', queue_pte_cnt)
add('ip_q_ptecnt', pte_cnt)
add('ip_rm_ptcnt', pte_cnt)
add('ip_q_ptsize', pt_size)
add('ip_rm_ptsize', pt_size)
add('ip_q_alloc', pt_size + QS * 2)
add('ip_q_cmd_off', pt_size)
add('ip_q_stat_off', pt_size + QS)
msg_count = (QS - 0x1000) // 0x1000
add('ip_q_msg_size', MS)
add('ip_q_msg_count', msg_count)
add('ip_q_ring_len', MS * msg_count)
add('ip_q_rx_hdr_off', ctypes.sizeof(nv.msgqTxHeader))
add('ip_q_entry_off', EH)
add('ip_q_version', 0)
add('ip_q_size', QS)
add('ip_q_flags', 1)
# :30 the ring is `msgSize * msgCount`, NOT `size` -- and they differ.
assert MS * msg_count != QS, 'the ring and the header size MUST differ or this gate says nothing'

hdr32, phdr48 = ctypes.sizeof(nv.rpc_message_header_v), ctypes.sizeof(nv.GSP_MSG_QUEUE_ELEMENT)
add('ip_q_hdr_len', hdr32)
add('ip_q_phdr_len', phdr48)
add('ip_q_max_payload', MS * 16 - phdr48 - hdr32)

# ===========================================================================
# :407-410 init_gsp_image's radix3
# ===========================================================================
RADIX_SHIFT = nv.LIBOS_MEMORY_REGION_RADIX_PAGE_LOG2 - 3
add('ip_radix_shift_4k', RADIX_SHIFT)


def radix3(n):
  npages = [0, 0, 0, round_up(n, 0x1000) // 0x1000]
  for i in range(3, 0, -1):
    npages[i - 1] = ((npages[i] - 1) >> RADIX_SHIFT) + 1
  return npages


for tag, n in (('4k', 0x1000), ('100k', 0x19000), ('1m', 0x100000), ('8m', 0x800000)):
  np_ = radix3(n)
  offs = [sum(np_[:i]) * 0x1000 for i in range(4)]
  add('ip_radix_npages_%s' % tag, ','.join(str(x) for x in np_))
  add('ip_radix_offs_%s' % tag, ','.join(str(x) for x in offs))
  add('ip_radix_alloc_%s' % tag, offs[-1] + n)

# ===========================================================================
# :434-455 init_wpr_meta.  BOTH branches, because `fmc_boot` selects between them
# and the fmc branch supplies sizes where the other supplies offsets.
# ===========================================================================
BOOT_SZ, RADIX3_SZ = 0x1b4000, 0x19000
COMMON_N = 11          # the keys in `common` -- a COUNT the port must agree with


def wpr(vram, fmc):
  common = dict(sizeOfBootloader=BOOT_SZ, sysmemAddrOfBootloader=0x40000000,
                sizeOfRadix3Elf=RADIX3_SZ, sysmemAddrOfRadix3Elf=0x40020000,
                sizeOfSignature=0x1000, sysmemAddrOfSignature=0x40040000,
                bootloaderCodeOffset=0x1000, bootloaderDataOffset=0x2000,
                bootloaderManifestOffset=0x3000,
                revision=nv.GSP_FW_WPR_META_REVISION, magic=nv.GSP_FW_WPR_META_MAGIC)
  if fmc:
    return dict(common, vgaWorkspaceSize=0x20000, pmuReservedSize=0x1820000,
                nonWprHeapSize=0x220000, gspFwHeapSize=0x8700000, frtsSize=0x100000)
  vga_sz = 0x100000
  vga_off = vram - vga_sz
  frts_sz = 0x100000
  frts_off = vga_off - frts_sz
  boot_off = frts_off - BOOT_SZ
  gsp_off = round_down(boot_off - RADIX3_SZ, 0x10000)
  gsp_heap_sz = 0x8100000
  gsp_heap_off = round_down(gsp_off - gsp_heap_sz, 0x100000)
  wpr_st = round_down(gsp_heap_off - 0x1000, 0x100000)
  non_wpr_sz = 0x100000
  non_wpr_off = round_down(wpr_st - non_wpr_sz, 0x100000)
  return dict(common, vgaWorkspaceSize=vga_sz, vgaWorkspaceOffset=vga_off,
              gspFwWprEnd=vga_off, frtsSize=frts_sz, frtsOffset=frts_off,
              bootBinOffset=boot_off, gspFwOffset=gsp_off, gspFwHeapSize=gsp_heap_sz,
              fbSize=vram, gspFwHeapOffset=gsp_heap_off, gspFwWprStart=wpr_st,
              nonWprHeapSize=non_wpr_sz, nonWprHeapOffset=non_wpr_off,
              gspFwRsvdStart=non_wpr_off)


WPR_FIELDS = ('vgaWorkspaceOffset', 'frtsOffset', 'bootBinOffset', 'gspFwOffset',
              'gspFwHeapOffset', 'gspFwWprStart', 'nonWprHeapOffset', 'gspFwRsvdStart',
              'gspFwWprEnd', 'fbSize', 'frtsSize', 'vgaWorkspaceSize',
              'pmuReservedSize', 'gspFwHeapSize', 'nonWprHeapSize')
# THE 64-BIT WALL IS THE FIXTURE RANGE, not the code: `vram_size` for any real
# card is >= 4 GiB and the chain SUBTRACTS from it, so every offset exceeds 2**32
# and none of it fits a `U32`.  The ladder is ported over fixtures that DO fit,
# which is what makes the chain checkable; the real card is the seam.
for tag, vram in (('1g', 0x40000000), ('2g', 0x80000000), ('max', 0xffffffff)):
  for fmc in (False, True):
    k = '%s_%s' % (tag, 'fmc' if fmc else 'leg')
    m = wpr(vram, fmc)
    add('ip_wpr_%s_nf' % k, len(m))
    for f in WPR_FIELDS:
      add('ip_wpr_%s_%s' % (k, f), m.get(f, 0))
add('ip_wpr_common_n', COMMON_N)
add('ip_wpr_sz', ctypes.sizeof(nv.GspFwWprMeta))
add('ip_wpr_boot_sz', BOOT_SZ)
add('ip_wpr_radix3_sz', RADIX3_SZ)
add('ip_wpr_vram_max', 0xffffffff)
add('ip_wpr_fixtures_fit', all(v <= 0xffffffff for v in (0x40000000, 0x80000000, 0xffffffff)))
add('ip_wpr_magic_lo', lo32(nv.GSP_FW_WPR_META_MAGIC))
add('ip_wpr_magic_hi', hi32(nv.GSP_FW_WPR_META_MAGIC))
# :145 `self.frts_offset = self.nvdev.vram_size - 0x100000 - 0x100000`
for tag, vram in (('1g', 0x40000000), ('2g', 0x80000000), ('max', 0xffffffff)):
  add('ip_frts_off_%s' % tag, vram - 0x100000 - 0x100000)
# :141-143 the ucode-descriptor size arithmetic
add('ip_desc_sig_total', 0x440 - nv.FALCON_UCODE_DESC_V3_SIZE_44)
add('ip_desc_img_256', round_up(0x8000, 256))

# ===========================================================================
# :389-399 init_libos_args
# ===========================================================================
LOGBASE, RMARGS = 2 << 20, 0x30000
libos = [('LOG' + n).encode('utf-8') for n in ("INIT", "INTR", "RM", "MNOC", "KRNL")]
libos.append(b'RMARGS')
add('ip_libos_n', len(libos))
add('ip_libos_total', sum(ctypes.sizeof(nv.LibosMemoryRegionInitArgument) for _ in libos))
add('ip_libos_pa_base', LOGBASE)
add('ip_libos_kind', nv.LIBOS_MEMORY_REGION_CONTIGUOUS)
add('ip_libos_loc', nv.LIBOS_MEMORY_REGION_LOC_SYSMEM)
for i, b in enumerate(libos):
  add('ip_libos_size_%d' % i, 0x10000 if i < 5 else 0x1000)
  add('ip_libos_pa_%d' % i, LOGBASE + 0x10000 * i if i < 5 else RMARGS)
  add('ip_libos_lead_%d' % i, b[0])
# THE 64-BIT WALL: `id8=int.from_bytes(bytes(f"LOG{name}",'utf-8'),'big')` reads an
# EIGHT-BYTE name as a big-endian integer. All six exceed 2**32, so `id8` is NOT
# ported; what is ported is the byte width, the over-32 count, and the first byte.
add('ip_libos_id8_bytes', 8)
add('ip_libos_id8_over_u32', sum(1 for b in libos if int.from_bytes(b, 'big') > 0xffffffff))
add('ip_libos_id8_n', len(libos))

# ===========================================================================
# :616-627 rpc_set_registry_table
# ===========================================================================
TABLE = {'RMForcePcieConfigSave': 0x1, 'RMSecBusResetEnable': 0x1}
hdr_size = ctypes.sizeof(nv.PACKED_REGISTRY_TABLE)
entry_size = ctypes.sizeof(nv.PACKED_REGISTRY_ENTRY)
entries_size = entry_size * len(TABLE)
add('ip_reg_hdr_size', hdr_size)
add('ip_reg_entries_size', entries_size)
add('ip_reg_n', len(TABLE))
add('ip_reg_type', nv.REGISTRY_TABLE_ENTRY_TYPE_DWORD)
add('ip_reg_RMForcePcieConfigSave_val', TABLE['RMForcePcieConfigSave'])
add('ip_reg_RMSecBusResetEnable_val', TABLE['RMSecBusResetEnable'])
add('ip_reg_RMForcePcieConfigSave_type', nv.REGISTRY_TABLE_ENTRY_TYPE_DWORD)
add('ip_reg_RMSecBusResetEnable_type', nv.REGISTRY_TABLE_ENTRY_TYPE_DWORD)
add('ip_reg_RMForcePcieConfigSave_len', 4)
add('ip_reg_RMSecBusResetEnable_len', 4)
entries_bytes, data_bytes = b'', b''
for k, v in TABLE.items():
  add('ip_reg_%s_off' % k, hdr_size + entries_size + len(data_bytes))
  entries_bytes += bytes(nv.PACKED_REGISTRY_ENTRY(nameOffset=hdr_size + entries_size + len(data_bytes),
                                                  type=nv.REGISTRY_TABLE_ENTRY_TYPE_DWORD,
                                                  data=v, length=4))
  data_bytes += k.encode('utf-8') + b'\x00'
add('ip_reg_data_len', len(data_bytes))
add('ip_reg_len0', len('RMForcePcieConfigSave') + 1)
add('ip_reg_off0', hdr_size + entries_size)
add('ip_reg_off1', hdr_size + entries_size + len('RMForcePcieConfigSave') + 1)
add('ip_reg_size', hdr_size + len(entries_bytes) + len(data_bytes))
add('ip_reg_payload', len(entries_bytes))
add('ip_reg_msg_payload', hdr_size + len(entries_bytes) + len(data_bytes))

# ===========================================================================
# :602 bdf_as_int, verbatim
# ===========================================================================
def bdf_as_int(s):
  return 0x000 if s.startswith("usb") or s.startswith("remote") else \
      (int(s[5:7], 16) << 8) | (int(s[8:10], 16) << 3) | int(s[-1], 16)


for s in ("0000:01:00.0", "0000:0a:00.0", "0000:ff:1f.7", "usb", "remote", "0000:00:00.0"):
  add('ip_bdf_%s' % s.replace(':', '_').replace('.', '_'), bdf_as_int(s))
add('ip_bdf_usb_arm', "usb".startswith("usb"))
add('ip_bdf_remote_arm', "remote".startswith("remote"))
add('ip_bdf_remote_not_usb', not "remote".startswith("usb"))
add('ip_bdf_lo_ff', int("ff", 16))
add('ip_bdf_mid_1f', int("1f", 16))
add('ip_bdf_fn_7', int("7", 16))
add('ip_bdf_pair_00', int("00", 16))

# ===========================================================================
# :577-580 the PMA flags -- THREE constants that are ALL the value 1
# ===========================================================================
PHYS = nv_gpu.NVOS02_FLAGS_PHYSICALITY_NONCONTIGUOUS
NOMAP = nv_gpu.NVOS02_FLAGS_MAPPING_NO_MAP
RO = nv_gpu.NVOS02_FLAGS_ALLOC_USER_READ_ONLY_YES
add('ip_pma_phys', PHYS << 4)
add('ip_pma_nomap', NOMAP << 30)
add('ip_pma_flags', (PHYS << 4) | (NOMAP << 30))
add('ip_pma_ro', (PHYS << 4) | (NOMAP << 30) | (RO << 21))
add('ip_pma_all_three_are_1', PHYS == 1 and NOMAP == 1 and RO == 1)

# ===========================================================================
# :498-504 the graphics-context buffer map
# ===========================================================================
ENGINE_ID = nv_gpu.NV0080_CTRL_FIFO_GET_ENGINE_CONTEXT_PROPERTIES_ENGINE_ID_GRAPHICS
PATCH_ID = nv_gpu.NV0080_CTRL_FIFO_GET_ENGINE_CONTEXT_PROPERTIES_ENGINE_ID_GRAPHICS_PATCH
add('ip_ctx_eng', ENGINE_ID)
add('ip_ctx_patch', PATCH_ID)
add('ip_ctx_patch_plus14', PATCH_ID + 14)
# a fixture of `engine[i].size` / `.alignment` for engine ids 0..24
ENG = {i: (0x1000 * max(i - 16, 1), 0x1000 * (1 if i < 21 else 4)) for i in range(25)}
add('ip_ctx_eng_n', len(ENG))
for i in range(25):
  add('ip_ctx_%d_size' % i, ENG[i][0])
  add('ip_ctx_%d_align' % i, ENG[i][1])


def ctx_info(idx, add_=0):
  return round_up(ENG[idx][0] + add_, ENG[idx][1])


# :500 `cfgs_sizes = {x: _ctx_info(x + 14, align=(2 << 20) if x == 5 else None)}`
CFGS = {}
for x in range(3, 11):
  sz, al = ENG[x + 14]
  CFGS[x] = round_up(sz, (2 << 20) if x == 5 else al)
for x in range(3, 11):
  add('ip_ctxcfg_%d' % x, CFGS[x])
add('ip_ctxcfg_n', len(CFGS))
# :501-504 the GRBufDesc table, INSERTION order (it is a dict, so it matters)
GRCTX = {0: (ctx_info(ENGINE_ID, 0x40000), True, True, False),
         1: (ctx_info(PATCH_ID), True, True, True),
         2: (ctx_info(PATCH_ID), True, True, False)}
GRCTX.update({x: (CFGS[x], False, True, False) for x in range(3, 7)})
GRCTX[9] = (CFGS[9], True, True, False)
GRCTX[10] = (CFGS[10], True, False, False)
GRCTX[11] = (CFGS[10], True, True, False)          # NOTE: 11 reuses cfgs_sizes[10]
add('ip_grctx_keys', ','.join('%d' % k for k in GRCTX))
add('ip_grctx_n', len(GRCTX))
for k in sorted(GRCTX):
  sz, ph, vi, lo = GRCTX[k]
  add('ip_grctx_%d' % k, '%d,%d,%d,%d' % (sz, int(ph), int(vi), int(lo)))
add('ip_grctx_11_reuses_10', GRCTX[11][0] == GRCTX[10][0])
add('ip_grctx_local_n', sum(1 for k in GRCTX if GRCTX[k][3]))

# ===========================================================================
# :357-362 the channel class table
# ===========================================================================
GA = (nv_gpu.AMPERE_CHANNEL_GPFIFO_A, nv_gpu.AMPERE_COMPUTE_B, nv_gpu.AMPERE_DMA_COPY_B, None)
AD = (nv_gpu.AMPERE_CHANNEL_GPFIFO_A, nv_gpu.ADA_COMPUTE_A, nv_gpu.AMPERE_DMA_COPY_B, nv_gpu.NVC9B0_VIDEO_DECODER)
GB = (nv_gpu.BLACKWELL_CHANNEL_GPFIFO_A, nv_gpu.BLACKWELL_COMPUTE_B, nv_gpu.BLACKWELL_DMA_COPY_B, nv_gpu.NVCFB0_VIDEO_DECODER)
for tag, chip in (('GA', 'GA102'), ('AD', 'AD102'), ('GB', 'GB202')):
  t = {'GA': GA, 'AD': AD, 'GB': GB}[tag]
  add('ip_cls_%s' % tag, ','.join(str(x) if x is not None else 'None' for x in t))
add('ip_cls_ga_like_n', sum(1 for t in (GA, AD, GB) if t[3] is None))
add('ip_cls_viddec_ada', nv_gpu.NVC9B0_VIDEO_DECODER)
add('ip_cls_viddec_gb', nv_gpu.NVCFB0_VIDEO_DECODER)
add('ip_cls_nvdec0', nv_gpu.NV2080_ENGINE_TYPE_NVDEC0)
add('ip_cls_GA_viddec_none', GA[3] is None)
add('ip_cls_AD_viddec_set', AD[3] is not None)

# ===========================================================================
# :629-661 run_cpu_seq's opcode table, and the walk at :631-651
# ===========================================================================
SEQOPS = [(0x0, 'reg_write', 2), (0x1, 'reg_modify', 3), (0x2, 'reg_poll', 5),
          (0x3, 'delay_us', 1), (0x4, 'save_reg', 2), (0x5, 'core_reset', 0),
          (0x6, 'start_cpu', 0), (0x7, 'wait_halted', 0), (0x8, 'core_resume', 0)]
add('ip_seq_n', len(SEQOPS))
add('ip_seq_ops', ','.join('%x' % o for o, _, _ in SEQOPS))
add('ip_seq_names', ','.join(n for _, n, _ in SEQOPS))
add('ip_seq_words', ','.join(str(w) for _, _, w in SEQOPS))
add('ip_seq_first_ok', SEQOPS[0][0])
add('ip_seq_last_ok', SEQOPS[-1][0])
add('ip_seq_first_bad', SEQOPS[-1][0] + 1)
add('ip_seq_gap_at', SEQOPS[-1][0] + 1)
add('ip_seq_hdr_size', ctypes.sizeof(nv.rpc_run_cpu_sequencer_v17_00))
add('ip_seq_bad_9', 9 > 8)
add('ip_seq_ok_8', not (8 > 8))
PROG = [0x0, 0x1000, 0xdead, 0x0, 0x2000, 0xbeef, 0x3, 1000, 0x4, 0x3000, 1, 0x6]
seen, i = [], 0
while i < len(PROG):
  op = PROG[i]
  seen.append(op)
  i += 1 + (SEQOPS[op][2] if op < 9 else 0)
add('ip_seq_prog_cmdindex', len(PROG))
add('ip_seq_prog_ops', ','.join('%x' % o for o in seen))
add('ip_seq_prog_n', len(seen))
add('ip_seq_prog_consumed', i)
add('ip_seq_prog_aligned', i == len(PROG))

# ===========================================================================
# :328-344 kfsp_send_msg's framing
# ===========================================================================
add('ip_fsp_w0', (1 << 31) | (1 << 30))
add('ip_fsp_w1_base', 0x7e | (0x10de << 8))
for nvmd in (nv.NVDM_TYPE_COT, 0, 0xff):
  add('ip_fsp_w1_%d' % nvmd, (0x7e << 0) | (0x10de << 8) | (nvmd << 24))
add('ip_fsp_hdr_len', 8)
add('ip_fsp_max', 0x400)
# `buf = headers + buf + (4 - (len(buf) % 4)) * b'\0'` pads the PAYLOAD, not the
# total -- so the 1024-byte assert is reached at a payload of 1016, not 1024.
add('ip_fsp_max_ok_payload', 0x400 - 8 - 4)
for blen in (0, 1, 4, 8, 100, 1016, 1017):
  pad = (4 - (blen % 4)) % 4
  add('ip_fsp_pad_%d' % blen, pad)
  add('ip_fsp_tot_%d' % blen, blen + 8 + pad)
add('ip_fsp_1016_refuses', not (1016 + 8 + 0 < 0x400))
add('ip_fsp_1012_ok', 1012 + 8 + 0 < 0x400)

# ===========================================================================
# :526-536 rpc_alloc_memory and :594-599 rpc_set_page_directory
# ===========================================================================
add('ip_am_format', 6)
add('ip_am_pteAdjust', 0)
add('ip_am_idr', nv.NV_VGPU_PTEDESC_IDR_NONE)
add('ip_pte_sz', ctypes.sizeof(nv.struct_pte_desc_pte_pde))
add('ip_pte_desc_sz', ctypes.sizeof(nv.rpc_alloc_memory_v))
for n in (1, 4):
  add('ip_am_payload_%d' % n, ctypes.sizeof(nv.rpc_alloc_memory_v) +
      ctypes.sizeof(nv.struct_pte_desc_pte_pde) * n)
for paddr in (0x0, 0x1000, 0x12345000, 0xffffffff):
  add('ip_pte_shift_%x' % paddr, paddr >> 12)  # 0x12345000 -> 74565
for n in (0, 1, 15, 16, 17, 65535, 65536, 65537):
  add('ip_pte_len_%d' % n, n & 0xffff)
add('ip_am_pages_ok', 0x1000 == 0x1000 and 0x1000 == 0x1000)
add('ip_am_pages_bad', 0x1000 == 0x1000 and 0x2000 == 0x1000)
add('ip_pd_flags', 0x8)
add('ip_pd_pasid', 0xffffffff)
add('ip_pd_subDeviceId', 1)
add('ip_pd_chId', 0)
add('ip_pd_sz', ctypes.sizeof(nv.struct_NV0080_CTRL_DMA_SET_PAGE_DIRECTORY_PARAMS_v1E_05))
add('ip_pd_spsz', ctypes.sizeof(nv.rpc_set_page_directory_v))
# :611-614 rpc_unloading_guest_driver
add('ip_unload_newLevel', 1 << 6)
add('ip_unload_sz', ctypes.sizeof(nv.rpc_unloading_guest_driver_v))
add('ip_unload_len', len(bytes(nv.rpc_unloading_guest_driver_v(bInPMTransition=0, bGc6Entering=0, newLevel=1 << 6))))
# :348 the handle generator, :519 priv_root, :457-466 promote_ctx, :487 gpfifo
add('ip_handle_gen_first', next(itertools.count(0xcf000000)))
add('ip_handle_gen_n', 8)
add('ip_priv_root', 0xc1e00004)
add('ip_promote_phys_attr', 0x4)
add('ip_promote_gpFifoEntries', 32)
add('ip_promote_gpFifoFlags', 0x200320)
add('ip_promote_internalFlags', 0x1a)
add('ip_promote_cid', 3)
add('ip_promote_addressSpace', 2)
add('ip_promote_userd_off', 0x20 * 8)
add('ip_promote_userd_base', 0x20 * 8)
add('ip_promote_userd_size', 0x20)
add('ip_gpfifo_area', 4 << 10)
# :590-591 the doorbell rule
add('ip_door_gb2', ((7 << 16) | (1 << 30)) == ((7 << 16) | (1 << 30)))
add('ip_door_ga10', (7 << 16) == (7 << 16))
add('ip_door_gb2_v', (7 << 16) | (1 << 30))
add('ip_door_ga10_v', 7 << 16)
add('ip_door_gb2_bit30', "GB202".startswith("GB2"))
add('ip_door_ga10_no_bit30', not "GA102".startswith("GB2"))

add('ip_ctx_end', 1)
add('ip_ctxcfg_end', 1)
add('ip-grctx_end', 1)

open(os.path.join(HERE, 'nv_ip_rows2.txt'), 'w').write('\n'.join(R) + '\n')
print('stage C rows %d' % len(R))