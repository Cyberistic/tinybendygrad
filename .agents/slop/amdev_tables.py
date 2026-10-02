#!/usr/bin/env python3
"""amdev_tables.py -- EMIT the DATA tables of amdev.bend from CPython.

Three tables are pure data and a hand transcription of them is exactly the
failure this project has been burned by (ops_nv: 33 of 219 constants wrong in a
file already printing 590 green rows), so they are generated:

  * the STRUCT FIELD LISTS, by name and IN ORDER, with their byte offsets --
    `am.py`'s own `register_fields` for the offsets and `_real_fields_` for the
    names, which are two independent transcriptions of the same layout.
  * `hwid_names` (:400), BOTH directions, including the UVD_HWID/VCN_HWID
    collision at value 12 which the comprehension silently drops.
  * `hw_id_map` (:380), BOTH directions, including hw_id 108 mapping to BOTH
    14 and 26.

    .venv/bin/python .agents/slop/amdev_tables.py > /tmp/tbl.bend
"""
import sys, re, inspect
sys.path.insert(0, '.')
from tinygrad.runtime.autogen.am import am

AMSRC = inspect.getsource(sys.modules[am.__name__])

def rf(cls):
  m = re.search(rf"^{cls}\.register_fields\(\[.*?\]\)", AMSRC, re.M)
  return re.findall(r"\('([^']+)',\s*[^,]+,\s*(\d+)\)", m.group(0))

def names(cls):
  return [f[0] if isinstance(f, tuple) else f for f in getattr(am, cls)._real_fields_]

# the structs amdev.py itself reads, in the order it reads them.
SEC = [
  ("common_firmware_header", 'struct_common_firmware_header', ":33 :47 :57 :68 :86 :91 -- load_fw's version probe and every image's first member"),
  ("binary_header",         'struct_binary_header',         ":365 the discovery image's root; table_list is indexed by IP_DISCOVERY/HARVEST_INFO/GC"),
  ("ip_discovery_header",   'struct_ip_discovery_header',   ":366 :372 :375 the die walk and the base_addr_64_bit flag that sets the stride"),
  ("die_header",            'struct_die_header',            ":373 :375 the per-die IP count, and the size that starts the IP array"),
  ("ip_v4",                 'struct_ip_v4',                 ":377 :380 :382 ONE discovered IP: its hw_id, its instance, and its (major,minor,revision)"),
  ("gc_info_v1_0",          'struct_gc_info_v1_0',          ":395-396 the GC table, re-read as struct_gc_info_v{major}_{minor}"),
  ("psp_fw_bin_desc",       'struct_psp_fw_bin_desc',       ":37 ONE entry of the SOS bin array; the four members are read at :38-39"),
  ("smc_soft_pptable_entry",'struct_smc_soft_pptable_entry',":51 one soft-pptable entry; :53 matches `id` against the P2S magic"),
  ("psp_firmware_v2_1",     'struct_psp_firmware_header_v2_1', ":33-36 psp_fw_bin_count and, when header_version_minor == 1, psp_aux_fw_bin_index"),
  ("smc_firmware_v2_1",     'struct_smc_firmware_header_v2_1', ":47-51 pptable_count and pptable_entry_offset; the v1_0 prefix is at 0"),
  ("sdma_firmware_v1_0",    'struct_sdma_firmware_header_v1_0', ":57-60 the v1 arm: header.ucode_array_offset_bytes and header.ucode_size_bytes"),
  ("sdma_firmware_v2_0",    'struct_sdma_firmware_header_v2_0', ":62-63 the v2 arm: ctl_ucode_offset/size THEN ctx_ucode_size_bytes, both the struct's OWN members"),
  ("gfx_firmware_v1_0",     'struct_gfx_firmware_header_v1_0', ":68-75 the v1 arm: ucode_size_bytes - jt_size*4 for code, then ucode_off + jt_offset*4 for JT"),
  ("gfx_firmware_v2_0",     'struct_gfx_firmware_header_v2_0', ":78-82 the v2 arm: its OWN ucode_size_bytes, data_offset/size, and the 64-bit ucode_start_addr"),
  ("imu_firmware_v1_0",     'struct_imu_firmware_header_v1_0', ":86-88 IMU_I at iram and IMU_D at iram_offset + iram_size"),
  ("rlc_firmware_v2_1",     'struct_rlc_firmware_header_v2_1', ":95-97 the three LIST_SRM_CNTL/LIST_GPM_MEM/LIST_SRM_MEM save-restore pairs"),
  ("rlc_firmware_v2_2",     'struct_rlc_firmware_header_v2_2', ":100-101 the IRAM and DRAM_BOOT pairs"),
  ("rlc_firmware_v2_3",     'struct_rlc_firmware_header_v2_3', ":104-107 the P and V pairs"),
]

def emit_table(key, cls, note):
  ns, rf_ = names(cls), rf(cls)
  on = [n for n, _ in rf_]
  # `register_fields` lists the SCALAR members only -- a nested struct (`header`,
  # `v2_0`) or an array (`table_list`, `die_info`, `psp_fw_bin`) is in
  # `_real_fields_` and NOT in it, and the scalars are INTERSPERSED among those, not
  # gathered at the front (`struct_ip_discovery_header` puts `reserved2` last and
  # drops `padding`/`base_addr_64_bit` entirely). So the relation is: `onnames` is
  # `names` FILTERED to the scalars, in order, and `offs` is strictly increasing --
  # which is what says the layout is packed in declaration order.
  assert [n for n in ns if n in set(on)] == on, (cls, ns, on)
  oi = [int(o) for _, o in rf_]
  assert all(oi[i] < oi[i+1] for i in range(len(oi)-1)), (cls, rf_)
  out = [f"# {note}", f"def sf.{key}.names() -> List<&2, String>: [{', '.join(chr(34)+n+chr(34) for n in ns)}]",
         f"def sf.{key}.offs() -> List<&2, U32>: [{', '.join(str(o) for o in oi)}]",
         f"def sf.{key}.onnames() -> List<&2, String>: [{', '.join(chr(34)+n+chr(34) for n in on)}]",
         f"def sf.{key}.n() -> U32: {len(ns)}",
         f"def sf.{key}.nscalar() -> U32: {len(rf_)}",
         f"def sf.{key}.size() -> U32: {getattr(am, cls).SIZE}",
         f"def sf.{key}.maxoff() -> U32: {max(oi)}"]
  return "\n".join(out)

print("# the STRUCT FIELD LISTS, BY NAME AND IN ORDER, with their byte offsets.")
print("# `names` is `_real_fields_`; `offs` is the generator's own `register_fields`,")
print("# which lists the SCALAR members ONLY -- a nested struct or an array is in the")
print("# first list and not the second, and the scalars are INTERSPERSED among those")
print("# rather than gathered at the front. So the load-bearing claim is that")
print("# `onnames` is `names` FILTERED to the scalars, in order, and `offs` rises")
print("# strictly: that is what says the layout is packed in declaration order, and")
print("# an INVERTED list breaks it while a field COUNT would not.")
for key, cls, note in SEC:
  print(emit_table(key, cls, note))
  print()

# ---- hwid_names and hw_id_map, BOTH directions ----------------------------
hk = [k for k in vars(am) if k.endswith('_HWID') and isinstance(vars(am)[k], int)]
hv = [vars(am)[k] for k in hk]
print("# `hwid_names` (:400) is `{v: k.removesuffix('_HWID') ...}`, a value -> NAME")
print("# table, and :382 never uses it -- so the port carries the reverse name ->")
print("# value too, because a firmware blob's hw_id is a VALUE and a diagnostic's")
print("# is a NAME. THE COLLISION IS THE POINT: UVD_HWID and VCN_HWID are BOTH 12,")
print("# so the comprehension DROPS UVD, and `hwid_names` has 77 entries for 78 keys.")
print(f"def hwid.names() -> List<&2, String>: [{', '.join(chr(34)+k.removesuffix('_HWID')+chr(34) for k in hk)}]")
print(f"def hwid.vals() -> List<&2, U32>: [{', '.join(str(v) for v in hv)}]")
print(f"def hwid.nkeys() -> U32: {len(hk)}")
print(f"def hwid.ndistinct() -> U32: {len(set(hv))}")
coll = [v for v, c in __import__('collections').Counter(hv).items() if c > 1]
print(f"def hwid.ncollision() -> U32: {len(coll)}")
print(f"def hwid.collision() -> U32: {coll[0] if coll else 0}")
print(f"def hwid.collision_names() -> List<&2, String>: [{', '.join(chr(34)+k.removesuffix('_HWID')+chr(34) for k in hk if vars(am)[k]==coll[0])}]")
print()
# `hw_id_map` (:380), the discovery gate, both directions
m = am.hw_id_map
inv = {v: k for k, v in m.items()}
print("# `hw_id_map` (:380) is hw_ip -> hw_id and is read as `am.hw_id_map[hw_ip]")
print("# == ip.hw_id`. :391 builds its INVERSE for the harvest table, and 108 is in")
print("# BOTH 14 (NBIO) and 26 (NBIF), so the inverse's 108 is whichever comes last.")
print(f"def hwip.hwips() -> List<&2, U32>: [{', '.join(str(k) for k in sorted(m))}]")
print(f"def hwip.ids() -> List<&2, U32>: [{', '.join(str(m[k]) for k in sorted(m))}]")
print(f"def hwip.n() -> U32: {len(m)}")
print(f"def hwip.inv_n() -> U32: {len(inv)}")
print(f"def hwip.inv_108() -> U32: {inv[108]}")
print(f"def hwip.dupvals() -> List<&2, U32>: [{', '.join(str(v) for v, c in __import__('collections').Counter(m.values()).items() if c > 1)}]")
print(f"def hwip.max() -> U32: {max(m)}")
print(f"def hwip.in_range() -> U32: {len([k for k in range(1, am.MAX_HWIP) if k in m])}")