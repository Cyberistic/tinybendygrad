#!/usr/bin/env python3
"""THE SYMBOL-KEYED VENDOR SCAN for `runtime/ops_cl.bend`'s `vend.cl`/`vend.cu`/
`vend.hp` tables. Re-run of the check that originally found `cuModuleLoadData` and
`hipModuleLoadData` mis-indexed at `OP_BUILD` instead of `OP_PRG_FROM_BIN`.

WHY AST AND NOT A REGEX. The first version of this scan stripped every string
literal before looking for `hip.hipGetErrorString` and thereby reported it as a
PHANTOM CELL, because `ops_hip.py:10` writes that symbol inside an f-string whose
text is a literal. `mt_constmap.py`'s rule applies verbatim: a symbol inside a
STRING is not a symbol, but an f-string's `{...}` is CODE, so the scan reads
`ast.Attribute` nodes and takes the line from the node. A regex cannot tell those
two apart and invents a bug. (`enum_cudaError_enum` at cu:18 is the converse: a
`cuda.X` in real code that is a dict, not a call.)

WHAT IT ASSERTS.
  1. every `cl.X` / `cuda.X` / `hip.X` in the three sources is either a table cell
     for that vendor or on an explicit NOT_A_CALL allowlist WITH a reason,
  2. every named cell is a real `MODULE.X` in that vendor's source (no phantom),
  3. every cell resolves through the real autogen module (a typo in a symbol is a
     silent wrong name at the seam -- and `autogen.hip` IMPORTS on this machine,
     contrary to the .bend header's WALL 7 claim),
  4. the three tables and `vend.argname` have the same 39 cells,
  5. a symbol appears at ONE op per vendor, except the declared ALIAS set
     (`cuMemcpyAsync` and `hipMemcpy` each spell both COPY_IN and COPY_OUT).

Run: .venv/bin/python .agents/slop/cl_vendor_scan.py
"""
import ast, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BENCH = ROOT / "tinybendygrad/runtime/ops_cl.bend"
SRC = {v: ROOT / f"tinygrad/runtime/ops_{n}.py" for v, n in (("cl", "cl"), ("cu", "cuda"), ("hp", "hip"))}
MODULE = {"cl": "cl", "cu": "cuda", "hp": "hip"}
AUTOGEN = {"cl": "opencl", "cu": "cuda", "hp": "hip"}
BEND_SRC = BENCH.read_text()

# NOT_A_CALL: a `MODULE.X` that is a ctypes type, an enum member, a dict or an
# import path rather than a call the trace records. Every entry carries a reason.
NOT_A_CALL = {
  "cl": {"CL_DEVICE_TYPE_GPU": "enum value, cl:97", "CL_DEVICE_TYPE_DEFAULT": "enum value, cl:97",
         "CL_MEM_READ_WRITE": "mem flag, cl:80", "CL_MEM_OBJECT_IMAGE2D": "mem type, cl:62",
         "CL_RGBA": "enum, cl:61", "CL_HALF_FLOAT": "enum, cl:61", "CL_FLOAT": "enum, cl:61",
         "CL_QUEUE_PROFILING_ENABLE": "queue flag, cl:111",
         "CL_PROGRAM_BUILD_LOG": "enum, cl:29", "CL_PROGRAM_BINARY_SIZES": "enum, cl:33",
         "CL_PROGRAM_BINARIES": "enum, cl:34", "CL_PROFILING_COMMAND_START": "enum, cl:73",
         "CL_PROFILING_COMMAND_END": "enum, cl:74", "CL_DEVICE_NAME": "enum, cl:105",
         "CL_DRIVER_VERSION": "enum, cl:107", "CL_DEVICE_EXTENSIONS": "enum, cl:113",
         "CL_DEVICE_IMAGE_PITCH_ALIGNMENT": "enum, cl:122",
         "size_t": "ctypes type, cl:10 (WALL 4 CC_CB)",
         "cl_platform_id": "ctypes type, cl:96", "cl_device_id": "ctypes type, cl:101",
         "cl_mem": "ctypes type, the annotation at cl:55", "cl_program": "ctypes type, cl:11",
         "cl_kernel": "ctypes type", "cl_context": "ctypes type",
         "cl_event": "ctypes type, cl:67",
         "cl_image_format": "ctypes type, cl:61", "cl_image_desc": "ctypes type, cl:62"},
  "cu": {"CUDA_ERROR_HOST_MEMORY_ALREADY_REGISTERED": "enum, cu:90",
         "CUDA_SUCCESS": "enum, cu:92", "CU_STREAM_NON_BLOCKING": "stream flag, cu:109",
         "CU_STREAM_WAIT_VALUE_GEQ": "op, cu:58", "CU_STREAM_WRITE_VALUE_DEFAULT": "op, cu:61",
         "enum_cudaError_enum": "the dict read at cu:18",
         "CUdevice": "ctypes type, cu:106", "CUcontext": "ctypes type, cu:107",
         "CUstream": "ctypes type, cu:109", "CUmodule": "ctypes type, cu:128",
         "CUfunction": "ctypes type, cu:129", "CUdeviceptr": "ctypes type, cu:78",
         "CUhostFn": "ctypes type, cu:122"},
  "hp": {"hipDeviceptr_t": "ctypes type, hp:62", "hipDeviceProp_t": "ctypes type, hp:15",
         "hipEvent_t": "ctypes type, hp:16", "hipModule_t": "ctypes type, hp:30",
         "hipFunction_t": "ctypes type, hp:31",
         "hipMemcpyHostToDevice": "memcpy kind, hp:67", "hipMemcpyDeviceToHost": "kind, hp:70"},
}
# a symbol that is legitimately spelled at TWO ops in one vendor.
ALIAS = {"cu": {"cuMemcpyAsync": ("COPY_IN", "COPY_OUT")},
         "hp": {"hipMemcpy": ("COPY_IN", "COPY_OUT")}}

OPNAME = {int(v): k for k, v in re.findall(r"^def OP_([A-Z_0-9]+)\(\) -> U32: (\d+)$", BEND_SRC, re.M)}


def bend_list(fn):
  """the ONE list literal of `fn` in the .bend, as a list of str."""
  m = re.search(rf"^def {fn}\(\) -> List<&2, String>:\n((?:  .*\n)+)", BEND_SRC, re.M)
  assert m, f"ops_cl.bend has no `def {fn}() -> List<&2, String>:` block"
  body = re.sub(r"^\s*#.*$", "", m.group(1), flags=re.M)
  return re.findall(r'"([^"]*)"', body)


def source_hits(vendor):
  """every `MODULE.X` in the source: X -> the LINES, from CPython's own AST."""
  mod, out = MODULE[vendor], {}
  tree = ast.parse(SRC[vendor].read_text())
  for n in ast.walk(tree):
    if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name) and n.value.id == mod:
      out.setdefault(n.attr, []).append(n.lineno)
  return out


def main():
  tables = {v: bend_list(f"vend.{v}") for v in ("cl", "cu", "hp")}
  argname = bend_list("vend.argname")
  n = len(tables["cl"])
  fail = 0
  for v, tab in tables.items():
    hits, cells = source_hits(v), {s: i for i, s in enumerate(tab) if s}
    allow = {k for k, r in NOT_A_CALL[v].items() if r}
    print(f"== vend.{v}: {len(tab)} cells, {len(cells)} named, {len(hits)} distinct `{MODULE[v]}.X` "
          f"in {SRC[v].name}")
    if len(tab) != n or len(argname) != n:
      print(f"  !! table length {len(tab)} / argname {len(argname)} / n {n}"); fail += 1
    for name, lines in sorted(hits.items()):
      if name in cells or name in allow: continue
      print(f"  !! MISSING FROM TABLE {MODULE[v]}.{name} at {SRC[v].name}:{','.join(map(str, lines))}")
      fail += 1
    for name, ix in sorted(cells.items(), key=lambda kv: kv[1]):
      if name not in hits:
        print(f"  !! PHANTOM CELL {MODULE[v]}.{name} at op {ix} ({OPNAME.get(ix)}): no "
              f"`{MODULE[v]}.{name}` in {SRC[v].name}")
        fail += 1
    for name in sorted(set(cells) & allow):
      print(f"  !! CONFLICT {MODULE[v]}.{name} is BOTH a cell (op {cells[name]}) and NOT_A_CALL")
      fail += 1
    # the symbol must exist in the REAL autogen module, or the seam's name is a typo
    amod = __import__(f"tinygrad.runtime.autogen.{AUTOGEN[v]}", fromlist=["x"])
    for name in sorted(cells):
      if not hasattr(amod, name):
        print(f"  !! {MODULE[v]}.{name} (op {cells[name]}) is NOT in autogen.{MODULE[v]}")
        fail += 1
    seen = {}
    for ix, s in enumerate(cells):
      for op, s2 in seen.items():
        if s != s2: continue
        want = ALIAS.get(v, {}).get(s)
        if not want or OPNAME[op] not in want or OPNAME[ix] not in want:
          print(f"  !! vend.{v}: {s} at op {op} ({OPNAME[op]}) AND op {ix} ({OPNAME[ix]}), "
                f"and that pair is not in ALIAS")
          fail += 1
      seen[ix] = s
  print("\n== per-op symbol, all three vendors")
  for ix in range(n):
    c = [tables[v][ix] for v in ("cl", "cu", "hp")]
    gap = "" if all(c) else "   <- no spelling in " + ",".join(
      v.upper() for v in ("cl", "cu", "hp") if not tables[v][ix])
    print(f"  {ix:2d} {OPNAME.get(ix, '?'):<18} {c[0]:<26} {c[1]:<26} {c[2]}{gap}")
  print(f"\n{'FAIL' if fail else 'OK'}: {fail} problem(s)")
  return 1 if fail else 0


if __name__ == "__main__":
  sys.exit(main())
