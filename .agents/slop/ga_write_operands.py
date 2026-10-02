#!/usr/bin/env python3
"""Port `write_operands`' arch-dependent head, generate.py:464-482.

THE INHERITED FILE DROPPED TWO OF write_operands' DECISIONS:

  1. `valid = {(name, fmt) for fmt, ops in enums.items() for name in ops.values()}`
     and `if (name, enc_base) not in valid: continue` -- the OPERANDS table is
     keyed by (instruction name, encoding format), and the XML carries entries
     whose name is not an opcode of that format's enum.  Without the filter the
     port emitted `VOP3P_MFMAOp.V_MFMA_LD_SCALE_B32`, which is not a member of
     `VOP3P_MFMAOp`, so the generated Python would not even import.
  2. `enum_names = sorted(f"{k}Op" for k in used_bases)` and the
     `from ...{arch}.enum import ...` line -- the emitter's signature had lost
     `enums` and `arch`, so the import list could not be built at all and the
     line was missing from the output.

Neither is visible in a row that only checks the ROWS of the table; both are
visible in the `operands rdna3` emitter row, which is the whole file.

Run:  python3 .agents/slop/ga_write_operands.py <file.bend>
"""
import pathlib
import sys

BLOCK = '''
# ======================================================================
# `write_operands`, generate.py:464-482.  TWO DECISIONS THE INHERITED FILE
# DID NOT MAKE, and both are visible only in the whole-file gate row:
#   * `valid` -- the set of (instruction NAME, encoding FORMAT) pairs that the
#     ENUM TABLE actually declares.  The XML carries `types` entries whose name
#     is not an opcode of that format's enum, and `OPERANDS` keys them by
#     `<fmt>Op.<name>`, so an unfiltered row is a reference to a member that
#     does not exist and the generated Python does not import.  The fixture has
#     exactly one: `("V_MFMA_LD_SCALE_B32", "VOP3P_MFMA")`, because the
#     `VOP3P_MFMA` enum declares `V_MFMA_F32_16X16X1F32`, not that name.
#   * `enum_names` -- `sorted(f"{k}Op" for k in used_bases)`, which is why
#     `HWREGOp`/`MSGOp` appear in the import even though no row uses them: they
#     ARE row keys, as `HWREGOp.HWREG_VCCZ`.
# ======================================================================

type VF is Data: VF{name: String, fmt: String}

def VF.name(v: VF) -> String:
  match v:
    case VF{name, fmt}: name

def VF.fmt(v: VF) -> String:
  match v:
    case VF{name, fmt}: fmt

def vf_one(+v: VF, +nm: String, +fmt: String) -> Bool:
  Bool.and(String.eq(VF.name(v), nm), String.eq(VF.fmt(v), fmt))

def vf_hit(vs: List<&2, VF>, +nm: String, +fmt: String) -> Bool:
  match vs:
    case Nil{}: False{}
    case +v <> t: Bool.or(vf_one(v, nm, fmt), vf_hit(t, nm, fmt))

def valid_pairs.ops(os_: List<&2, OP>, +fmt: String, acc: List<&2, VF>) -> List<&2, VF>:
  match os_:
    case Nil{}: acc
    case +o <> t: valid_pairs.ops(t, fmt, List.append(&2, VF, acc, [VF{OP.nm(o), fmt}]))

def valid_pairs.eos(eos: List<&2, EO>, acc: List<&2, VF>) -> List<&2, VF>:
  match eos:
    case Nil{}: acc
    case +e <> t: valid_pairs.eos(t, List.append(&2, VF, acc, valid_pairs.ops(EO.ops(e), EO.fmt(e), Nil{})))

def valid_pairs(eos: List<&2, EO>) -> List<&2, VF>:
  valid_pairs.eos(eos, Nil{})

# `{eb for (nm, eb) in types if (nm, eb) in valid}` -- a SET, so the bases are
# deduplicated before the sort.  `dedup_adj` on the SORTED list is that set.
def used_bases.go(tys: List<&2, TY>, vs: List<&2, VF>, acc: List<&2, String>) -> List<&2, String>:
  match tys:
    case Nil{}: acc
    case +t <> rest: used_bases.go(rest, vs,
      Bool.pick(List<&2, String>, vf_hit(vs, TY.name(t), TY.base(t)),
        List.append(&2, String, acc, [TY.base(t)]), acc))

def used_bases(tys: List<&2, TY>, vs: List<&2, VF>) -> List<&2, String>:
  dedup_adj(sort_strs(used_bases.go(tys, vs, Nil{})))

def write_operands.enum_names(tys: List<&2, TY>, eos: List<&2, EO>) -> List<&2, String>:
  sort_strs(used_bases.ops(tys, eos))

def used_bases.ops(tys: List<&2, TY>, eos: List<&2, EO>) -> List<&2, String>:
  used_bases.names.go(used_bases(tys, valid_pairs(eos)), Nil{})

def used_bases.names.go(bs: List<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match bs:
    case Nil{}: acc
    case +b <> t: used_bases.names.go(t, List.append(&2, String, acc, [b ++ "Op"]))

# THE RECURSION IS AN ARGUMENT, NOT AN ARM OF THE PICK.  `Bool.pick` CHOOSES
# between two already-computed values and never sequences one, so writing the
# self-call inside a pick arm means the walk stops at the first element whose
# accumulator happens to be chosen -- `dedup_adj(["a","a","b","b","c"])` answered
# `["a"]`.  Only the ACCUMULATOR is a pick; the walk is unconditional.
def dedup_adj.step(+x: String, +last: String, acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.eq(x, last), acc, List.append(&2, String, acc, [x]))

def dedup_adj.go(xs: List<&2, String>, +last: String, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +x <> t: dedup_adj.go(t, x, dedup_adj.step(x, last, acc))

def dedup_adj(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case +x <> t: dedup_adj.go(t, x, [x])

def write_operands.keep(t: TY, vs: List<&2, VF>) -> Bool:
  vf_hit(vs, TY.name(t), TY.base(t))

def write_operands.rows.go(tys: List<&2, TY>, vs: List<&2, VF>, acc: List<&2, String>) -> List<&2, String>:
  match tys:
    case Nil{}: acc
    case +t <> rest: write_operands.rows.go(rest, vs,
      Bool.pick(List<&2, String>, write_operands.keep(t, vs),
        List.append(&2, String, acc,
          ["  " ++ TY.base(t) ++ "Op." ++ TY.name(t) ++ ": {" ++
           String.join(write_operands.cells(sort_ois(TY.flds(t))), ", ") ++ "},"]), acc))

def write_operands(tys: List<&2, TY>, eos: List<&2, EO>, +arch: String) -> List<&2, String>:
  write_operands.tail(
    write_operands.rows.go(sort_tys(tys), valid_pairs(eos), Nil{}), [
      "# autogenerated from AMD ISA XML - do not edit",
      "from tinygrad.runtime.autogen.amd.common import Fmt, OpType",
      "from tinygrad.runtime.autogen.amd." ++ arch ++ ".enum import " ++
        String.join(write_operands.enum_names(tys, eos), ", "), ""])
'''


def main(path):
    p = pathlib.Path(path)
    s = p.read_text()
    old = '''def write_operands(tys: List<&2, TY>) -> List<&2, String>:
  write_operands.tail(write_operands.rows(sort_tys(tys)), [
    "# autogenerated from AMD ISA XML - do not edit", ""])
'''
    assert old in s, "the inherited one-argument write_operands is not there"
    s = s.replace(old, "", 1)
    # the old rows walk is superseded by the filtered one
    for dead in ('''def write_operands.rows(tys: List<&2, TY>) -> List<&2, String>:
  write_operands.rows.go(tys, Nil{})

''', '''def write_operands.rows.go(tys: List<&2, TY>, acc: List<&2, String>) -> List<&2, String>:
  match tys:
    case Nil{}: acc
    case +t <> +rest:
      write_operands.rows.go(rest, List.append(&2, String, acc,
        ["  " ++ TY.base(t) ++ "Op." ++ TY.name(t) ++ ": {" ++
         String.join(write_operands.cells(sort_ois(TY.flds(t))), ", ") ++ "},"]))

'''):
        assert dead in s, dead.split("\n")[0]
        s = s.replace(dead, "", 1)
    # the gate banner starts the generated tail; the block goes above it
    at = s.index("# THE GATE.")
    at = s.rindex("# =====", 0, at)
    s = s[:at] + BLOCK.strip("\n") + "\n\n" + s[at:]
    p.write_text(s)
    print("write_operands head ported: %d lines" % len(s.split("\n")))


if __name__ == "__main__":
    main(sys.argv[1])