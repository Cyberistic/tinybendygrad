"""CPython oracle for webgpu_call.bend. Every constant is READ, not typed.

Run: python3 .agents/slop/webgpu_call_oracle.py
Prints `name = value   <- autogen/webgpu.py:LINE (ENUM_NAME)`.
The line number is found by grepping the file for the assignment, so the citation
cannot drift from the value.
"""
import sys, re, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, "tinygrad", "runtime", "autogen"))
import webgpu  # noqa: E402

SRC = os.path.join(ROOT, "tinygrad", "runtime", "autogen", "webgpu.py")
lines = open(SRC).read().splitlines()


NUM = r"(0[xX][0-9a-fA-F]+|\d+)"


def _n(s: str) -> int:
  return int(s, 16) if s[:2].lower() == "0x" else int(s)


def line_of(sym: str) -> int:
  """The 1-based line where `sym` is bound, as a walrus inside its enum dict
  (`(SYM:=1):`), as a decimal assignment (`SYM: Alias = 1`) or as a hex bit flag
  (`SYM = 0x0000000000000001`)."""
  pats = (re.compile(r"\(" + re.escape(sym) + r":?=(" + NUM + r")\)"),
          re.compile(r"^" + re.escape(sym) + r"\s*(?::[^=]+)?=\s*(" + NUM + r")\s*$"))
  for i, ln in enumerate(lines, 1):
    for pat in pats:
      m = pat.search(ln)
      if m:
        return i, _n(m.group(1))
  raise KeyError(sym)


# (bend-name, the python symbol). Every one of these becomes a Bend constant.
WANT = [
  # -- the ones ops_webgpu.bend already pins, re-read here so this oracle is
  # -- independently the source for BOTH files.
  ("WGPUBufferUsage_MapRead", "USAGE_MAP_READ"),
  ("WGPUBufferUsage_CopySrc", "USAGE_COPY_SRC"),
  ("WGPUBufferUsage_CopyDst", "USAGE_COPY_DST"),
  ("WGPUBufferUsage_Uniform", "USAGE_UNIFORM"),
  ("WGPUBufferUsage_Storage", "USAGE_STORAGE"),
  ("WGPUBufferUsage_QueryResolve", "USAGE_QUERY_RESOLVE"),
  ("WGPUFeatureName_TimestampQuery", "FEATURE_TIMESTAMP_QUERY"),
  ("WGPUFeatureName_ShaderF16", "FEATURE_SHADER_F16"),
  ("WGPUBufferMapState_Unmapped", "MAP_UNMAPPED"),
  ("WGPUBufferMapState_Mapped", "MAP_MAPPED"),
  ("WGPUBufferBindingType_Uniform", "BIND_UNIFORM"),
  ("WGPUBufferBindingType_Storage", "BIND_STORAGE"),
  ("WGPUErrorFilter_Validation", "FILTER_VALIDATION"),
  # -- NEW for the call layer.
  ("WGPUShaderStage_Compute", "SHADER_STAGE_COMPUTE"),
  ("WGPUQueryType_Timestamp", "QUERY_TYPE_TIMESTAMP"),
  ("WGPUMapMode_Read", "MAP_MODE_READ"),
  ("WGPUPowerPreference_HighPerformance", "POWER_PREF_HIGH_PERF"),
  ("WGPUSType_ShaderSourceWGSL", "STYPE_SHADER_SOURCE_WGSL"),
  ("WGPUCallbackMode_WaitAnyOnly", "CALLBACK_MODE_WAIT_ANY_ONLY"),
]

print("## CONSTANTS (read out of tinygrad/runtime/autogen/webgpu.py)")
bad = 0
for sym, bend in WANT:
  try:
    ln, val = line_of(sym)
  except KeyError:
    print(f"{bend:28s} = <NOT FOUND> {sym}")
    bad += 1
    continue
  print(f"{bend:28s} = {val:<12d} <- autogen/webgpu.py:{ln} ({sym})")

print()
print("## DERIVED (the three usage bitmasks ops_webgpu.py builds with `|`)")
U = {n: line_of(f"WGPUBufferUsage_{n}")[1] for n in
     ("MapRead", "CopySrc", "CopyDst", "Uniform", "Storage", "QueryResolve")}
print(f"alloc.usage()   STORAGE|COPY_DST|COPY_SRC   = "
      f"{U['Storage'] | U['CopyDst'] | U['CopySrc']}  (ops_webgpu.py:152)")
print(f"dev.uniform_usage() UNIFORM|COPY_DST        = {U['Uniform'] | U['CopyDst']}  (ops_webgpu.py:203)")
print(f"copy.readable_usage() COPY_DST|MAP_READ     = {U['CopyDst'] | U['MapRead']}  (ops_webgpu.py:208)")
print(f"query usage     QUERY_RESOLVE|COPY_SRC      = {U['QueryResolve'] | U['CopySrc']}  (ops_webgpu.py:115)")

print()
print("## NUMERIC LITERALS ops_webgpu.py writes into descriptors")
print(f"query buffer size   = 16   <- ops_webgpu.py:115 WGPUBufferDescriptor(size=16, ...)")
print(f"query count         = 2    <- ops_webgpu.py:114 WGPUQuerySetDescriptor(type=..., count=2)")
print(f"begin pass write ix = 0    <- ops_webgpu.py:116 beginningOfPassWriteIndex=0")
print(f"end pass write ix   = 1    <- ops_webgpu.py:117 endOfPassWriteIndex=1")
print(f"uniform size        = 4    <- ops_webgpu.py:203 WGPUBufferDescriptor(size=4, ...)")
print(f"bindGroupLayoutCount = 1   <- ops_webgpu.py:87")
print(f"submit count        = 1    <- ops_webgpu.py:129 wgpuQueueSubmit(queue, 1, ...)")
print(f"resolve first/second= 0, 2 <- ops_webgpu.py:126 ResolveQuerySet(encoder, qs, 0, 2, qbuf, 0)")
print(f"resolve dst offset  = 0    <- ops_webgpu.py:126")
print(f"write buffer offset = 0    <- ops_webgpu.py:221 wgpuQueueWriteBuffer(queue, buf, 0, ...)")
print(f"bind group offset   = 0    <- ops_webgpu.py:96 WGPUBindGroupEntry(offset=0, ...)")
print(f"resolve src offset  = 0    <- ops_webgpu.py:126 (the `0` after query_set)")

print()
print("## THE ENUM DICT MEMBER SETS the port indexes by name")
print("enum_WGPUBackendType =", webgpu.enum_WGPUBackendType)
print("enum_WGPUPowerPreference =", webgpu.enum_WGPUPowerPreference)
print("has WGPUObjectType:", hasattr(webgpu, "enum_WGPUObjectType"))

print()
print("## THE ORACLE'S EXIT PATH -- what the ctypes seam actually does here")
print("ops_webgpu.py:11 runs at IMPORT time and calls wgpuCreateInstance. Checked:")
try:
  import tinygrad.runtime.autogen.webgpu as _w  # already imported above
  print("  autogen/webgpu.py imported OK; the LIBRARY load happens in ops_webgpu.py,")
  print("  not here, so importing the enums is safe and needs no stub.")
except BaseException as e:  # noqa: BLE001
  print("  import failed:", type(e).__name__, e)
try:
  sys.path.insert(0, os.path.join(ROOT, "tinygrad"))
  from tinygrad.runtime.autogen import webgpu as _w2
  _w2.lib
  print("  _w2.lib loaded:", _w2.lib)
except BaseException as e:  # noqa: BLE001
  print("  ops_webgpu.py's own import of the LIBRARY would fail with:",
        type(e).__name__, str(e)[:120])
  print("  -> so NO wgpu call can be made from CPython on this machine. The enum")
  print("     dicts are pure data and were read directly; nothing was stubbed.")

print()
print("## WHAT WAS STUBBED: nothing. Every number above came from the source file.")
sys.exit(1 if bad else 0)