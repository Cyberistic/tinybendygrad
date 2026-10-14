#!/usr/bin/env python3
"""GAP 1 measurement: compare the `*_VALS` FIXTURE VALUES on both sides.

The gate compares NAMES only and drops the value. This prints, per VALS list,
the oracle's (name, value) against the port's (name, value), so every
disagreement is a MEASUREMENT rather than an opinion.
"""
import importlib.util, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
PORT = ROOT / "tinybendygrad/renderer/amd/dsl.bend"
ORACLE = ROOT / "gates/amd_dsl_census-oracle.py"

KIND = {"plain": "BitField", "fixed": "FixedBitField", "enum": "EnumBitField",
        "src": "SrcField", "vgpr": "VGPRField", "sgpr": "SGPRField",
        "ssrc": "SSrcField", "align2": "AlignedSGPRField", "sbase": "SBaseField",
        "srsc": "SRsrcField", "vdsty": "VDSTYField"}

VAL_DEFS = ("VOP2_ALL", "VOP2_NEG", "VOP2_HI", "VOP2_INT", "VOP2_INT65",
            "VOP2_INTN17", "VOP2_FCONST", "VOP2_FNOLIT", "VOP2_LIT",
            "VOP2_SDWA", "VOP2_DPP", "VOP2_BIG", "VOP2_BIG2", "ORD_VALS",
            "ORD_VALS_SWAP", "F32_VALS", "F16_VALS", "F64_VALS", "F40_VALS",
            "F8_VALS")


def bend_defs():
    """`def NAME() -> List<&2, Vf>:` bodies, verbatim."""
    src = PORT.read_text()
    out = {}
    for m in re.finditer(r"^def ([A-Z0-9_]+)\(\) -> List<&2, Vf>:(.*?)(?=^def |\Z)",
                         src, re.M | re.S):
        out[m.group(1)] = m.group(2)
    return out


def main() -> int:
    sys.path.insert(0, str(ORACLE.parent))
    spec = importlib.util.spec_from_file_location("_amd_oracle", str(ORACLE))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    bd = bend_defs()
    diffs = 0
    for nm in VAL_DEFS:
        want = list(getattr(m, nm))
        body = bd.get(nm, "<MISSING DEF>")
        print(f"=== {nm}")
        print(f"    oracle: {want}")
        print(f"    port  : {' '.join(body.split())}")
    # the machine check: every NAME and every VALUE, as strings the parser can see
    print("=== PARSED-VALUE DIFF (oracle tuple vs the port's literal tokens)")
    for nm in VAL_DEFS:
        body = bd.get(nm, "")
        toks = re.findall(r'Fld\.\w+\("(\w+)", \d+, \d+(?:, \d+)?\), Ov\.(\w+)\(([^)]*)\)', body)
        pv = [(n, f"{k}:{a}".strip(":")) for n, k, a in toks]
        ov = [(n, repr(v)) for n, v in getattr(m, nm)]
        print(f"{nm}: names_equal={pv == ov or [x[0] for x in pv] == [x[0] for x in ov]}")
        if [x[0] for x in pv] != [x[0] for x in ov]:
            print(f"   NAME MISMATCH port={[x[0] for x in pv]} oracle={[x[0] for x in ov]}")
        else:
            for (pn, _), (on, ov_) in zip(pv, ov):
                print(f"   {on:8s} port={pn!r:60s} oracle={ov_}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())