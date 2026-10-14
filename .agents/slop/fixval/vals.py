#!/usr/bin/env python3
"""GAP 1: normalize EVERY `*_VALS` fixture VALUE on both sides and diff.

Every spelling is CLOSED: an unknown one raises.  A normalizer that quietly
drops what it does not recognise is the same bug as the gate's, one level down.
"""
import importlib.util, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "gates"))
spec = importlib.util.spec_from_file_location(
    "_o", str(ROOT / "gates/amd_dsl_census-oracle.py"))
o = importlib.util.module_from_spec(spec)
spec.loader.exec_module(o)

PORT = ROOT / "tinybendygrad/renderer/amd/dsl.bend"
NAMES = ("VOP2_ALL", "VOP2_NEG", "VOP2_HI", "VOP2_INT", "VOP2_INT65",
         "VOP2_INTN17", "VOP2_FCONST", "VOP2_FNOLIT", "VOP2_LIT", "VOP2_SDWA",
         "VOP2_DPP", "VOP2_BIG", "VOP2_BIG2", "ORD_VALS", "ORD_VALS_SWAP",
         "F32_VALS", "F16_VALS", "F64_VALS", "F40_VALS", "F8_VALS")

U32 = lambda v: v & 0xFFFFFFFF
src = PORT.read_text()
U32_DEFS = {m.group(1): int(m.group(2))
            for m in re.finditer(r"^def (\w+)\(\) -> U32: (\d+)$", src, re.M)}
print("U32 literal defs resolved:", U32_DEFS)

BODY = {m.group(1): m.group(2) for m in re.finditer(
    r"^def ([A-Z0-9_]+)\(\) -> List<&2, Vf>:(.*?)(?=^def |\Z)", src, re.M | re.S)}


def u32_of(tok: str) -> int:
    tok = tok.strip().removesuffix("()")
    if tok.isdigit():
        return int(tok)
    if tok in U32_DEFS:
        return U32_DEFS[tok]
    raise KeyError(f"unresolved U32 token {tok!r}")


def port_value(tok: str) -> str:
    t = tok.strip()
    m = re.fullmatch(r"Ov\.int\((.*)\)", t)
    if m:
        return f"int:{U32(u32_of(m.group(1)))}"
    m = re.fullmatch(r"Ov\.none\(\)", t)
    if m:
        return "none"
    m = re.fullmatch(r"Ov\.reg\((\S+),\s*(\S+),\s*(\w+\{\}),\s*(\w+\{\}),\s*(\w+\{\})\)", t)
    if m:
        off, sz, neg, ab, hi = m.groups()
        b = lambda x: "1" if x == "True{}" else ("0" if x == "False{}" else None)
        f = tuple(b(x) for x in (neg, ab, hi))
        if None in f:
            raise KeyError(f"non-literal Bool in {t!r}")
        return f"reg:{u32_of(off)},{u32_of(sz)},{f[0]},{f[1]},{f[2]}"
    m = re.fullmatch(r"src_ov_float\(([^,]*),\s*(\w+\{\})\)", t)
    if m:
        known = m.group(2) == "True{}"
        # dsl.py:164 `self._FLOAT_ENC.get(val, 255)`: known False is the .get miss
        return f"float:{u32_of(m.group(1)) if known else 255}"
    raise KeyError(f"unclosed port value spelling {t!r}")


def oracle_value(v) -> str:
    if v is None:
        return "none"
    if isinstance(v, bool):
        raise KeyError("bool")
    if isinstance(v, int):
        return f"int:{U32(v)}"
    if isinstance(v, float):
        return f"float:{o.dsl.SrcField._FLOAT_ENC.get(v, 255)}"
    if isinstance(v, o.dsl.Reg):
        return (f"reg:{U32(v.offset)},{U32(v.sz)},"
                f"{int(bool(v.neg))},{int(bool(v.abs_))},{int(bool(v.hi))}")
    raise KeyError(f"unclosed oracle value {v!r} of {type(v)}")


VF = re.compile(r'Vf\.of\(Fld\.\w+\("(\w+)", \d+, \d+(?:, \d+)?\),\s*'
                r'((?:src_ov_float\((?:\w+\(\)|\d+),\s*\w+\{\}\)|Ov\.[a-z]+\([^()]*\))),')

bad = 0
for nm in NAMES:
    toks = BODY.get(nm)
    if toks is None:
        print(f"{nm}: NO PORT DEF"); bad += 1; continue
    got = [(m.group(1), port_value(m.group(2))) for m in VF.finditer(toks)]
    want = [(n, oracle_value(v)) for n, v in getattr(o, nm)]
    gn, wn = [x[0] for x in got], [x[0] for x in want]
    if gn != wn:
        print(f"{nm}: NAME MISMATCH port={gn} oracle={wn}"); bad += 1; continue
    for (n, g), (_, w) in zip(got, want):
        if g != w:
            print(f"{nm}.{n}: port={g!r} oracle={w!r}")
            bad += 1
    print(f"{nm}: {len(got)} values, {'EXACT' if all(a[1]==b[1] for a,b in zip(got,want)) else 'DIFFERS'}")
print(f"\nVALUE DISAGREEMENTS: {bad}")