#!/usr/bin/env python3
"""THROWAWAY: the BEND lane's own fp16, measured.

`checks/gen/probe.js` is the bend2 EMITTER's output for the live `tinybendygrad/dtype.bend`
(its `fp16_f32$norm$` is the current source's rule, term for term), so running it
measures the Bend's own arithmetic without a `bend` compile.  The bundle's `cli(...)` and
`io_exit(...)` calls are removed FROM A COPY -- the artifact on disk is not touched --
and a driver is appended that calls the emitted functions.

Both directions, against CPython's own codec:
  half -> f32   the white-box `fp16_f32`, over the 2046 half subnormals
  f32 -> half   the white-box `fp16_encode`, over the f32 subnormal band
  the SEAM      `Dt.fp16` composed, over the f32 subnormal band
"""
import pathlib
import re
import shutil
import struct
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
BUNDLE = ROOT / "checks" / "gen" / "probe.js"

BEND_FP16_F32 = "$tinybendygrad$047dtype$058fp16_f32$"
BEND_FP16_ENC = "$tinybendygrad$047dtype$058fp16_encode$"
BEND_DT_FP16 = "$tinybendygrad$047dtype$058Dt$fp16$"

DRIVER = """
const out = [];
const P32 = (v) => new Uint32Array(new Float32Array([v]).buffer)[0] >>> 0;
for (const h of %H2F%) out.push(`h2f_${h.toString(16)} = ${%FP16F32%(h) >>> 0}`);
for (const p of %F16B%) {
  const b = %FP16ENC%((p >>> 16) & 0x8000, (p >>> 23) & 0xff, p & 0x7fffff);
  out.push(`f16b_${p.toString(16)} = ${b.toString(16).padStart(4, "0")}`);
  out.push(`seam_${p.toString(16)} = ${P32(%DTF16%(new Float32Array(new Uint32Array([p >>> 0]).buffer)[0])).toString(16).padStart(8, "0")}`);
}
console.log(out.join("\\n"));
"""


def rows_of(text: str) -> dict[str, str]:
    rows = {}
    for line in text.splitlines():
        k, sep, v = line.partition(" = ")
        if k and sep and v:
            rows[k] = v.strip()
    return rows


def of32(p: int) -> float:
    return struct.unpack("<f", struct.pack("<I", p & 0xFFFFFFFF))[0]


def f32_pattern(x: float) -> int:
    return struct.unpack("<I", struct.pack("<f", x))[0]


h2f = [h for h in range(0x10000) if (h & 0x7C00) == 0 and (h & 0x3FF) != 0]
band = sorted({e << 23 | m for e in range(102, 113)
                for m in (0, 1, 2, 0x200000, 0x3FFFFF, 0x400000, 0x7FFFFF)})
nan = [p for p in range(0x7F800000, 0x7F800000 + 0x800000) if p & 0x7FFFFF][:64]
f16b = band + nan

src = BUNDLE.read_text()
body = src[:src.rindex("cli(process.argv.slice(1));")]
with tempfile.TemporaryDirectory() as tmp:
    work = pathlib.Path(tmp)
    js = work / "bend.js"
    js.write_text(body + (DRIVER
                          .replace("%H2F%", str(h2f))
                          .replace("%F16B%", str(f16b))
                          .replace("%FP16F32%", BEND_FP16_F32)
                          .replace("%FP16ENC%", BEND_FP16_ENC)
                          .replace("%DTF16%", BEND_DT_FP16)))
    p = subprocess.run(["node", str(js)], capture_output=True, text=True, timeout=600)
    if p.returncode != 0:
        print(f"node exited {p.returncode}: {p.stderr[:600]}")
        raise SystemExit(1)
    bend = rows_of(p.stdout)

# THE ORACLE: CPython's own codec, CALLED.
d_h2f = [(h, f"{f32_pattern(struct.unpack('<e', struct.pack('<H', h))[0]):08x}",
          bend.get(f"h2f_{h:x}")) for h in h2f]
bad_h2f = [t for t in d_h2f if t[1] != t[2]]
print(f"BEND half->f32 (fp16_f32, white-box), {len(h2f)} half subnormals: "
      f"{len(bad_h2f)} disagree with CPython")
for h, o, b in bad_h2f[:6]:
    print(f"    h2f_{h:x}: oracle={o} bend={b}")
if bad_h2f:
    print(f"    ... and {len(bad_h2f) - 6} more")

d_enc = [(p, f"{struct.unpack('<H', struct.pack('<e', of32(p)))[0]:04x}",
          bend.get(f"f16b_{p:x}")) for p in band]
bad_enc = [t for t in d_enc if t[1] != t[2]]
print(f"BEND f32->half (fp16_encode, white-box), {len(d_enc)} band patterns: "
      f"{len(bad_enc)} disagree with CPython")
for p, o, b in bad_enc[:4]:
    print(f"    f16b_{p:x}: oracle={o} bend={b}")

d_seam = [(p, f"{f32_pattern(struct.unpack('<e', struct.pack('<e', of32(p)))[0]):08x}",
           bend.get(f"seam_{p:x}")) for p in band]
bad_seam = [t for t in d_seam if t[1] != t[2]]
print(f"BEND f32->half (Dt.fp16, THE SEAM), {len(d_seam)} band patterns: "
      f"{len(bad_seam)} disagree with CPython")
for p, o, b in bad_seam[:6]:
    print(f"    seam_{p:x}: oracle={o} bend={b}")

d_nan = [(p, f"{f32_pattern(struct.unpack('<e', struct.pack('<e', of32(p)))[0]):08x}",
          bend.get(f"seam_{p:x}")) for p in nan]
bad_nan = [t for t in d_nan if t[1] != t[2]]
print(f"BEND Dt.fp16 over {len(d_nan)} f32 NaN patterns: {len(bad_nan)} disagree "
      f"with CPython")

# THE DISTINCT-COUNT, for the Bend's map: INJECTIVE AND WRONG IS A DIFFERENT DEFECT
# FROM THE JS's, WHICH WAS NOT INJECTIVE AT ALL.
pats = [bend[f"h2f_{h:x}"] for h in h2f if h < 0x8000]
print(f"BEND half->f32 distinct f32 patterns over the {len(pats)} positive half "
      f"subnormals: {len(set(pats))}")
