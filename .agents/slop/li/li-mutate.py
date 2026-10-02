#!/usr/bin/env python3
"""Mutation and constant sweeps for tinybendygrad/renderer/llvmir.bend.

TWO TABLES, BOTH MEASURED, BOTH DIFFING WHOLE `name=value` LINES.

  * `rules`  -- one textual edit per PORTED RULE, plus three comment-only
    CONTROLS. A rules sweep finds the LOGIC defects; a constants sweep finds
    none of them (measured on `x86`), so both run and the blind lists are the
    deliverable.
  * `consts` -- `+1` on every numeric literal in the file's defs. Every ZERO is a
    blind spot with a reason, not a coverage claim.

THE HARNESS EDITS TEXT AND NOTHING ELSE. The patterns live in `PATTERNS` below as
`label|old|new`, one per line, split on the first two `|` -- so no pattern has to
survive a round trip through Python quoting, and a pattern that is not on disk is
reported MISSING rather than silently matching nothing. (`cstyle.bend` arrived with
215 hand-written expectations of which 17 were wrong; the cost of writing them by
hand is paid again by every harness.)

TWO MEASUREMENTS about `bin/bend` that cost a cycle each and are written down so
the next harness does not pay them again:
  * WITHOUT `--check-only` the interpreter prints the gate table on STDOUT and NO
    verdict anywhere, so a harness reading one stream for both sees neither.
  * `--check-only` sends `ALL PROOFS CHECK` to STDOUT and `SOME PROOFS FAIL` to
    STDOUT as well, and exits 1 on the 14 permanently-red `dtype.bend` laws -- so
    the FIRST LINE is the verdict and the exit status is not.

    .venv/bin/python .agents/slop/li/li-mutate.py rules
    .venv/bin/python .agents/slop/li/li-mutate.py consts
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BEND = ROOT / "tinybendygrad/renderer/llvmir.bend"

PATTERNS = r"""
# --- lt: the RENAME-PROOF type map
M1|lt.fp's 16-bit arm is half|case 12: "half"|case 12: "bfloat"
M2|lt.fp answers double at pri 13|case 13: "bfloat"|case 13: "double"
M3|lt.ints is bits // 8|String.concat(["i", U32.show(bits)])|String.concat(["i", U32.show(U32.div(bits, 8))])
M4|CONTROL a comment-only edit|# THE TWELVE CONVENTIONS|# THE TWELVE CONVENTIONS (control)
M5|lt.v's count arm is >= 1|U32.is_gt(count, 1)|U32.is_ge(count, 1)
M6|lt.v's count arm is dropped|String.concat(["<", U32.show(count), " x ", lt.of(d), ">"])|""
M7|lt.fp's 8-bit arm is 9|case 8: "i8"|case 9: "i8"
M8|lt.fp's catch-all is float|case _: "double"|case _: "float"
M9|lt.of weak-class catch-all is void|        case _: "KeyError"|        case _: "void"
# --- is_volatile
M10|ivol ORs instead of ANDs|Bool.and(is_param, vol)|Bool.or(is_param, vol)
M11|ivol ignores is_param|Bool.and(is_param, vol)|vol
M12|ivol ignores vol|Bool.and(is_param, vol)|is_param
M13|volsp's volatile arm has no space|"volatile ", ""|"volatile", ""
# --- lconst
M14|lconst_b0 is 7F/87 (the OR reading)|Bool.pick(String, pos, "7F", "FF")|Bool.pick(String, pos, "7F", "87")
M15|lconst_b0 swaps its arms|Bool.pick(String, pos, "7F", "FF")|Bool.pick(String, pos, "FF", "7F")
M16|lconst_b1 drops the nan quiet bit|Bool.pick(String, is_nan, "F8", "F0")|Bool.pick(String, is_nan, "F0", "F0")
M17|lconst_hex tail is 10 zeros|"000000000000"|"00000000000"
M18|lconst_hex drops the 0x|String.concat(["0x", lconst_b0(pos)|String.concat(["", lconst_b0(pos)
M19|lc.arm's fp8 arm is truncate|"dtype.float_to_fp8", "dtype.truncate"|"dtype.truncate", "dtype.truncate"
M20|lc.int FLOORS instead of truncating|F32.show(F32.trunc(x))|F32.show(F32.floor(x))
M21|lc.int prints the untruncated value|F32.show(F32.trunc(x))|F32.show(x)
M22|lc.arm floats answer int|Bool.pick(String, flt, Bool.pick(String, fp8, "dtype.float_to_fp8", "dtype.truncate"), "int")|Bool.pick(String, flt, Bool.pick(String, fp8, "dtype.truncate", "dtype.float_to_fp8"), "int")
# --- range_str
M23|lab keeps the %|String.drop(xn, 1n)|xn
M24|rstr.id drops the leading digit|def rstr.id(v: U32) -> String: U32.show(v)|def rstr.id(v: U32) -> String: U32.show(U32.div(v, 2))
M25|rstr.neg drops the m|String.concat(["m", U32.show(v)])|U32.show(v)
M26|rstr.go's separator is a dot|String.concat(["_", rstr.go(t, "")])|String.concat([".", rstr.go(t, "")])
# --- the rule counts
M27|br_rules's first arm is 19|18, br_rules.b(k))|19, br_rules.b(k))
M28|br_rules.b's 23 becomes 22|U32.is_eq(k, 1), 23, 5|U32.is_eq(k, 1), 22, 5
M29|br_rules.b's third arm is 6|U32.is_eq(k, 1), 23, 5|U32.is_eq(k, 1), 23, 6
# --- rule 1, extractelement
M30|br1 answers None for ALU|Bool.pick(String, is_alu,|Bool.pick(String, False{},
M31|br1 answers a line for every addrspace|Bool.pick(String, is_alu,|Bool.pick(String, True{},
M32|br1's index type is i64|", i32 ", U32.show(idx)]), "None")|", i64 ", U32.show(idx)]), "None")
M33|br1 drops the extractelement|" = extractelement "|" = load "
# --- rule 2, the predicated LOAD
M34|br2 drops volatile |_yes = load ", volsp(vol)|_yes = load "
M35|br2 phi drops the alt|, alt, ", ", xn, "_entry]"])|, "", ", ", xn, "_entry]"])
M36|br2's phi is a bare name|String.concat(["  ", xn, " = phi "|String.concat(["  ", lab(xn), " = phi "
M37|br2 swaps _load and _exit|", label ", xn, "_load, label ", xn, "_exit", nl()]),|", label ", xn, "_exit, label ", xn, "_load", nl()]),
M38|br2's entry label keeps the %|String.concat([lab(xn), "_entry:", nl()]),|String.concat([xn, "_entry:", nl()]),
M39|br2 branches on the node not the mask|String.concat(["  br i1 ", mask, ", label ", xn|String.concat(["  br i1 ", xn, ", label ", xn
# --- rules 3 and 4
M40|br4 swaps value and index|"  store ", volsp(vol), lt.t(d, cnt, False{}), " ", varn|"  store ", volsp(vol), lt.t(d, cnt, False{}), " ", idx
M41|br3 drops the volatile fragment|", xn, " = load ", volsp(vol)|", xn, " = load "
# --- rule 5, the STACK chain
M42|br5.name indexes every line|Bool.pick(String, U32.is_eq(U32.add(i, 1), n), xn,|Bool.pick(String, U32.is_eq(U32.add(i, 1), n), U32.show(i),
M43|br5.pred is poison at every i|Bool.pick(String, U32.is_eq(i, 0), "poison"|Bool.pick(String, U32.is_eq(i, 99), "poison"
M44|br5.pred indexes the CURRENT line|String.concat([xn, "_", U32.show(U32.sub(i, 1))]))|String.concat([xn, "_", U32.show(i)]))
M45|br5's element count is len(srcs)|lt.t(nth_d(sdts, 0), cnt, False{})|lt.t(nth_d(sdts, 0), U32.from_nat(List.length(&2, S.Dt, sdts)), False{})
# --- rules 6-10
M46|br6.same is always True|U32.is_eq(S.Dt.itemsize(d), S.Dt.itemsize(od))|True{}
M47|br8 types the RESULT od|" = call ", lt.of(d), " @llvm.trunc.|" = call ", lt.of(od), " @llvm.trunc.
M48|br9 never walls|Bool.pick(String, N.lop.has(op, d),|Bool.pick(String, True{},
M49|br10 reuses d0 three times|, ", ", lt.of(d1), " ", s1, ", ", lt.of(d2), " ", s2])|, ", ", lt.of(d0), " ", s1, ", ", lt.of(d0), " ", s2])
# --- rules 11-14
M50|br11's loop label is bare|String.concat(["  br label %loop_", lab(rn)|String.concat(["  br label loop_", lab(rn)
M51|br13 labels from the NAME not the axis id|"phi = add ", lt.of(d), " ", rn, ", 1"|"phi = add ", lt.of(d), " ", lab(rn), ", 1"
M52|br13's icmp bound is a literal|"cmp = icmp ult ", lt.of(d), " ", rn, ", ", bn|"cmp = icmp ult ", lt.of(d), " ", rn, ", 16"
M53|br14 drops the latch label|"  br label %loop_latch_", aid, nl(), "loop_exit_", aid, ":"])|"loop_exit_", aid, ":"])
# --- rules 15-17 and the AMD barrier
M54|br16 labels from the ENDIF own name|lab(ifn), nl()|lab(ifn), " "
M55|br17 drops the leading two spaces|-> String: "  fence seq_cst"|-> String: "fence seq_cst"
M56|amd2 drops the barrier's quotes|String.join(N.barrier(), nl())|String.join(N.barrier(), "")
M57|amd0 drops the trailing space|N.wi(is_l, x), "; "])|N.wi(is_l, x), ";"])
M58|amd3 drops the DOUBLE space|@f32_to_fp8(float  ", s|@f32_to_fp8(float ", s
M59|amd3 spells the i1 as 0 for bf8|", i1 ", U32.show(bf8), ")"])|", i1 ", Bool.pick(String, U32.is_eq(bf8, 1), "0", "1"), ")"])
M60|amd4 swaps bf8 and fp8|U32.is_eq(bf8, 1), "bf8", "fp8"|U32.is_eq(bf8, 1), "fp8", "bf8"
M61|amd4 drops the synthesized _i32|"_i32 = zext i8 ", s, " to i32"|"_i32 = zext i16 ", s, " to i32"
# --- fp8_index, BOTH directions
M62|fp8i is f8pos without the mod|U32.mod(f8pos(d), 2)|f8pos(d)
M63|fp8i tests is_fnuz instead of the position|U32.mod(f8pos(d), 2)|Bool.pick(U32, N.is_fnuz(d), 1, 0)
M64|f8pos.go starts at 1|f8pos.go(N.fp8s(), d, 0)|f8pos.go(N.fp8s(), d, 1)
M65|f8pos.go's miss is 0 not the sentinel|case Nil{}      : 4294967295|case Nil{}      : 0
M66|f8pos.miss's sentinel is 0|U32.is_eq(m, 4294967295)|U32.is_eq(m, 0)
M67|f8names emits no commas|",", f8names.go(t, "")|"", f8names.go(t, "")
# --- _render_fn
M68|rfn.slot's space is outside the conditional|Bool.pick(String, String.eq(abi, ""), "", String.concat([" ", abi]))|String.concat([" ", abi])
M69|rfn.define drops the #0|", sa, ") #0"])|", sa, ")"])
M70|sargs one's noalias keys on REG|Bool.pick(String, is_glob, " noalias", ""), " ", nm])|Bool.pick(String, is_glob, "", " noalias"), " ", nm])
M71|sargs drops the ptr star|lt.t(d, 1, is_glob), Bool.pick|lt.t(d, 1, False{}), Bool.pick
M72|rfn.all's tail is one string|["  ret void", "}"]|["  ret void}"]
M73|rfn.cat is a prefix not an append|List.append(&2, String, a, b)|b
# --- the footers
M74|ftr.amd prefixes the group size with a 0|=\"1,",|=\"0,",
M75|ftr.amd halves the size|U32.show(wg), "\" \"no-trapping-math|U32.show(U32.div(wg, 2)), "\" \"no-trapping-math
M76|prod seeds with 0 not 1|prod.go(ws, 1)|prod.go(ws, 0)
M77|ftr.cpu_part splits on nothing|String.split(ftr.cpu(), Char.from_u32(32))|String.split(ftr.cpu(), Char.from_u32(9))
M78|CONTROL a comment-only edit|# THE GATE PRIMITIVES.|# THE GATE PRIMITIVES (control).
M79|CONTROL a comment-only edit|# `AMDLLVMRenderer.is_rdna4` -- llvmir.py:273|# `AMDLLVMRenderer.is_rdna4` (control) -- llvmir.py:273
"""


def rules():
  out = []
  for raw in PATTERNS.strip("\n").split("\n"):
    raw = raw.strip()
    if not raw or raw.startswith("#"):
      continue
    tag, label, old, new = raw.split("|", 3)
    out.append((f"{tag:<4} {label}", old, new))
  return out


def run(src):
  """Compile, then interpret, and return the rows. TWO CALLS -- see the header for
  why. A file that does not compile is `None`, and the caller prints BROKE, so a
  broken mutant is never mistaken for "no rows moved"."""
  tmp = BEND.with_suffix(".mut.bend")
  tmp.write_text(src)
  try:
    chk = subprocess.run([str(ROOT / "bin/bend"), str(tmp), "--check-only"],
                         capture_output=True, text=True, timeout=600)
    if "ALL PROOFS CHECK" not in chk.stdout:
      return None, (chk.stdout + chk.stderr)[:900]
    out = subprocess.run([str(ROOT / "bin/bend"), str(tmp)], capture_output=True,
                         text=True, timeout=600)
  finally:
    tmp.unlink(missing_ok=True)
  return out.stdout.split("\n"), ""


def moved(base, other):
  if other is None:
    return None
  b = {ln.split(" = [")[0]: ln for ln in base if " = [" in ln}
  o = {ln.split(" = [")[0]: ln for ln in other if " = [" in ln}
  return sorted(k for k in set(b) | set(o) if b.get(k) != o.get(k))


CONSTS = re.compile(r'(?<![\w."])(\d{3,10})(?![\w.])')


def consts():
  src = BEND.read_text()
  base, err = run(src)
  if base is None:
    print("BASELINE DID NOT COMPILE\n" + err)
    return
  seen = set()
  out = []
  for m in CONSTS.finditer(src):
    v = m.group(1)
    if v in seen:
      continue
    seen.add(v)
    out.append((f"C{len(out) + 1:<3} literal {v} -> {int(v) + 1}",
                src[:m.start(1)] + str(int(v) + 1) + src[m.end(1):]))
  print(f"{len(out)} CONSTANTS SWEPT (one `+1` each), baseline {len(base) - 1} rows\n")
  zero = []
  for label, mutant in out:
    got, _ = run(mutant)
    if got is None:
      print(f"{label:<34} BROKE")
      continue
    mv = moved(base, got)
    if not mv:
      zero.append(label)
    print(f"{label:<34} {0 if mv is None else len(mv):>4}" +
          ("" if not mv else "   " + ", ".join(mv[:6]) + (" ..." if len(mv) > 6 else "")))
  print(f"\n{len(out) - len(zero)} of {len(out)} constants moved something; {len(zero)} blind.")
  for z in zero:
    print("  BLIND:", z)


if __name__ == "__main__":
  what = sys.argv[1] if len(sys.argv) > 1 else "rules"
  if what == "consts":
    consts()
    sys.exit(0)
  src = BEND.read_text()
  base, err = run(src)
  if base is None:
    print("BASELINE DID NOT COMPILE\n" + err)
    sys.exit(1)
  R = rules()
  print(f"{len(R)} MUTATIONS, baseline {len(base) - 1} rows\n")
  zero = []
  for label, old, new in R:
    n = src.count(old)
    if n == 0:
      print(f"{label:<56} MISSING  (pattern not on disk)")
      continue
    if n > 1:
      print(f"{label:<56} AMBIGUOUS ({n} sites)")
      continue
    got, e = run(src.replace(old, new, 1))
    if got is None:
      first = [ln for ln in e.split("\n") if ln.startswith("Error") or ln.startswith("- ")][:1]
      print(f"{label:<56} BROKE    {first[0][:60] if first else ''}")
      continue
    mv = moved(base, got)
    if not mv:
      zero.append(label)
    print(f"{label:<56} {0 if mv is None else len(mv):>4}" +
          ("" if not mv else "   " + ", ".join(mv[:3]) + (" ..." if len(mv) > 3 else "")))
  print(f"\n{len(R) - len(zero)} of {len(R)} moved something; {len(zero)} blind.")
  for z in zero:
    print("  BLIND:", z)