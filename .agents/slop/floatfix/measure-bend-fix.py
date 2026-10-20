#!/usr/bin/env python3
"""THROWAWAY: the BEND's fp16_f32, and the ONE-TOKEN fix, measured.

`dtype.bend:711-715` computes the exponent of a half subnormal's f32 as
`(31 - U32.log2(m)) + 103`.  bend2's stdlib `U32.log2`
(`references/bend/bend2/base.bend:1544`) is floor(log2 n) -- NOT the C's
`__builtin_clz`, which is 31 - floor(log2 n) -- so the Bend's exponent is
`(31 - L) + 103` where the C's is `L + 103`.

This measures the BEND's own emitted code (the bend2 emitter's output for the live
`tinybendygrad/dtype.bend`, `checks/gen/probe.js`), and then the SAME emitted code
with the `31 -` dropped -- one token -- to show what the fix does.  The artifact on
disk is NOT touched: both runs are on copies.
"""
import pathlib
import struct
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
BUNDLE = ROOT / "checks" / "gen" / "probe.js"
FP16_F32 = "$tinybendygrad$047dtype$058fp16_f32$"

DRIVER = """
const out = [];
for (const h of %H2F%) out.push(`h2f_${h.toString(16)} = ${(%FP16F32%(h) >>> 0).toString(16).padStart(8, "0")}`);
console.log(out.join("\\n"));
"""

# THE EMITTED EXPONENT, exactly as the bend2 emitter wrote it.
EMITTED = "const _x_2 = ((31 - _x_1) >>> 0);"
# THE SAME EXPRESSION WITH THE `31 -` DROPPED: the one-token fix.
FIXED = "const _x_2 = ((_x_1) >>> 0);"


def run(src: str, h2f: list[int]) -> dict[str, str]:
    body = src[:src.rindex("cli(process.argv.slice(1));")]
    with tempfile.TemporaryDirectory() as tmp:
        js = pathlib.Path(tmp) / "bend.js"
        js.write_text(body + (DRIVER.replace("%H2F%", str(h2f)).replace("%FP16F32%", FP16_F32)))
        p = subprocess.run(["node", str(js)], capture_output=True, text=True, timeout=600)
        if p.returncode != 0:
            raise SystemExit(f"node exited {p.returncode}: {p.stderr[:400]}")
    rows = {}
    for line in p.stdout.splitlines():
        k, sep, v = line.partition(" = ")
        if sep:
            rows[k] = v.strip()
    return rows


h2f = [h for h in range(0x10000) if (h & 0x7C00) == 0 and (h & 0x3FF) != 0]
oracle = {f"h2f_{h:x}": f"{struct.unpack('<I', struct.pack('<f', struct.unpack('<e', struct.pack('<H', h))[0]))[0]:08x}"
          for h in h2f}
src = BUNDLE.read_text()
print(f"the emitted exponent expression: {EMITTED!r} present: {src.count(EMITTED)} site(s)")

for tag, text in (("AS EMITTED", src), ("WITH THE `31 -` DROPPED", src.replace(EMITTED, FIXED))):
    rows = run(text, h2f)
    bad = [h for h in h2f if rows[f"h2f_{h:x}"] != oracle[f"h2f_{h:x}"]]
    pos = {rows[f"h2f_{h:x}"] for h in h2f if h < 0x8000}
    print(f"  {tag:<26} disagree with CPython {len(bad)}/{len(h2f)} | "
          f"distinct f32 patterns over the 1023 positive: {len(pos)} | "
          f"h2f_1 = {rows['h2f_1']} (oracle {oracle['h2f_1']})")
