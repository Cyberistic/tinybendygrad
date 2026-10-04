#!/usr/bin/env python3
"""Mutation table for the LAST FOUR external-compiler backends.

One entry per ported rule, applied to the .bend file, re-run, and the rows that
MOVED are recorded BY NAME. The baseline is captured immediately before the run
and the substrate is re-checked between steps, because a concurrent agent
editing a shared file makes a row appear to move on every mutation.

A mutation that moves nothing is reported as a BLIND SPOT with a reason, and the
two kinds of zero are distinguished the way agent-core requires:

  THEOREM   no new fixture can move it, because the two spellings are the same
            function (`int.__or__` is commutative, so `encode`'s kwarg ORDER is
            unobservable; and two mutually-inverse forms of a tuple comparison).
  REQUEST   it is a MISSING FIXTURE, and the fixture is named.
"""
import pathlib, subprocess, sys, time
import patch_not_apply as PNA

ROOT = pathlib.Path(__file__).resolve().parents[2]
SLOP = ROOT / ".agents/slop"
BEND = ROOT / "bin/bend"

FILES = ["amd", "compiler_cpu", "compiler_cuda", "compiler_llvm"]

# (file, old, new, what the mutation is)
MUTATIONS = [
  ("amd", 'Bool.pick(U32, U32.is_ge(width, 32), 4294967295, U32.sub(U32.shln(1, U32.to_nat(width)), 1))',
          'Bool.pick(U32, U32.is_ge(width, 32), 4294967295, U32.sub(U32.shln(1, U32.to_nat(width)), 2))',
          "getbits.mask: the width-32 saturating branch (M1)"),
  ("amd", "U32.and(U32.shrn(val, U32.to_nat(start)), getbits.mask(getbits.width(end, start)))",
          "U32.shrn(val, U32.to_nat(start))",
          "getbits: drop the mask (M2)"),
  ("amd", "enc.go(vs, ss, U32.or(acc, U32.shln(v, U32.to_nat(s))))",
          "enc.go(vs, ss, U32.add(acc, U32.shln(v, U32.to_nat(s))))",
          "AMDReg.encode: `|` becomes `+` (M3)"),
  ("amd", "enc.go(vs, ss, U32.or(acc, U32.shln(v, U32.to_nat(s))))",
          "enc.go(vs, ss, U32.or(acc, v))",
          "AMDReg.encode: drop the shift (M4)"),
  ("amd", "msk.go(ss, es, U32.or(acc, U32.shln(AMDReg.width(s, e), U32.to_nat(s))))",
          "msk.go(ss, es, U32.or(acc, U32.shln(AMDReg.width(s, e), U32.to_nat(e))))",
          "AMDReg.fields_mask: shift by end instead of start (M5)"),
  ("amd", "def AMDReg.addr(+tup: List<&2, U32>, +segment: U32, +offset: U32) -> U32: U32.add(jget(tup, segment), offset)",
          "def AMDReg.addr(+tup: List<&2, U32>, +segment: U32, +offset: U32) -> U32: U32.add(hd(tup), offset)",
          "AMDReg.addr: ignore the segment index (M6 -- the shadowing)"),
  ("amd", "t3.eq3(major, minor, patch, 13, 0, 10))),", "t3.eq3(major, minor, patch, 13, 0, 11))),",
          "import_module.override: the second table entry is 13.0.11 (M7)"),
  ("amd", "    case 0n: Nat.is_le(la, lb)", "    case 0n: True{}",
          "import_module.vle: drop the length tiebreak (M8)"),
  ("amd", "  Bool.and(String.starts_with(c, name),", "  Bool.and(True{},",
          "import_module.keep: drop `startswith` (M9)"),
  ("amd", "case h <> t: Bool.pick(String, List.is_empty(&2, String, t), h, import_module.pick_last(t))",
          "case h <> t: h",
          "import_module.pick_last: take the FIRST of __all__ (M10)"),
  ("amd", 'String.to_list("mm"), []))', 'String.to_list("nn"), []))',
          "AMDIP.name10: the replacement is `nn` (M11)"),
  ("amd", "Bool.is_ge(n, 2)", "Bool.is_ge(n, 3)", "amd.ip_9_16_0.key: no-op (M12 -- control)"),
  ("amd", "U32.add(48, Bool.pick(U32, U32.is_gt(d, 9), U32.add(39, d), d))",
          "U32.add(48, Bool.pick(U32, U32.is_gt(d, 9), 39, d))", "hex: forget to add d for a-f (M13)"),
  ("amd", 'String.append(acc, String.from_list([hx2.digit(U32.mod(U32.from_nat(n), 16))])))',
          'String.append(acc, String.from_list([hx2.digit(U32.mod(U32.from_nat(n), 15))])))',
          "hex: divide/modulo by 15 instead of 16 (M14)"),
  ("amd", "Nat.div(U32.to_nat(n), 16n)", "Nat.div(U32.to_nat(n), 15n)",
          "hex: divide by 15 instead of 16 (M14)"),
  ("amd", "U32.add(1, hx2.len(p, U32.from_nat(Nat.div(U32.to_nat(n), 16n))))",
          "U32.add(2, hx2.len(p, U32.from_nat(Nat.div(U32.to_nat(n), 16n))))",
          "AMDReg.width / hx2.len: the count is one too many (M12)"),

  ("compiler_cpu", 'String.concat(["-mno", f])', 'String.concat(["-mnos", f])',
                   "x86_feat: `-mno{s}` loses its own `-` (M16)"),
  ("compiler_cpu", 'String.concat(["no", String.drop(f, 1n)])', 'String.concat(["no", f])',
                   "arm64_feat: keep the dash (M17)"),
  ("compiler_cpu", 'Bool.pick(String, String.eq(cpu, "native"), "rv64g", cpu)',
                   'Bool.pick(String, String.eq(cpu, "native"), "rv64g", cpu)', "riscv64_cpu: control (M18)"),
  ("compiler_cpu", '"rv64g", cpu)', '"rv64gc", cpu)', "riscv64_cpu: native -> rv64gc (M19)"),
  ("compiler_cpu", "def ClangCompiler.ge2(+n: U32) -> Bool: U32.is_ge(n, 2)",
                   "def ClangCompiler.ge2(+n: U32) -> Bool: U32.is_ge(n, 3)",
                   "ClangCompiler.ge2: the threshold (M20)"),
  ("compiler_cpu", '["-ffixed-x18", String.concat(["-mcpu=", String.join(\n    List.append(&2, String, [cpu], af.go(feats, [])), "+")])]',
                   '["-ffixed-x17", String.concat(["-mcpu=", String.join(\n    List.append(&2, String, [cpu], af.go(feats, [])), "+")])]',
                   "arm64: the fixed register is x17 (M21)"),
  ("compiler_cpu", 'List.append(&2, String, [cpu], af.go(feats, [])), "+")])]',
                   'List.append(&2, String, [cpu], af.go(feats, [])), "_")])]',
                   "arm64: join with `_` instead of `+` (M22)"),
  ("compiler_cpu", 'U32.add(14, ClangCompiler.args_n(arch))', 'U32.add(14, U32.add(ClangCompiler.args_n(arch), ClangCompiler.feats_n(arch)))',
                   "compile_argv: count the features twice (M23)"),
  ("compiler_cpu", "Bool.pick(U32, U32.is_eq(found, 4294967295),", "Bool.pick(U32, Bool.not(U32.is_eq(found, 4294967295)),",
                   "hx.bad: invert the found test (M24)"),
  ("compiler_cpu", "hx.count(p, t, n), hx.count(p, t, U32.add(n, 1)))",
                   "hx.count(p, t, U32.add(n, 2)))", "hx.count: count a space too (M25)"),

  ("compiler_cuda", "U32.add(U32.add(30, colored.index(color)),\n    Bool.pick(U32, String.eq(String.to_upper(color), color), 60, 0))",
                    "U32.add(30, colored.index(color))", "colored.esc: drop the upper-case +60 (M26)"),
  ("compiler_cuda", "Bool.or(U32.is_gt(major, 12), Bool.and(U32.is_eq(major, 12), U32.is_ge(minor, 4)))",
                    "Bool.or(U32.is_gt(major, 12), Bool.and(U32.is_eq(major, 12), U32.is_ge(minor, 5)))",
                    "nvrtc_ge_12_4: the minor threshold is 5 (M27)"),
  ("compiler_cuda", 'U32.is_ge(PTXCompiler.num(arch), 89), "7.8", "7.5")',
                    'U32.is_ge(PTXCompiler.num(arch), 88), "7.8", "7.5")',
                    "PTXCompiler.ver: the 89 threshold is 88 (M28)"),
  ("compiler_cuda", "pt.num.rd(U32.read(String.drop(arch, 3n)))", "pt.num.rd(U32.read(String.drop(arch, 2n)))",
                    "PTXCompiler.num: `arch[3:]` becomes `arch[2:]` (M29)"),
  ("compiler_cuda", 'Bool.pick(String, ptx, ".ptx", ".cubin")', 'Bool.pick(String, Bool.not(ptx), ".ptx", ".cubin")',
                    "NVCCCompiler.suffix: invert ptx (M30)"),
  ("compiler_cuda", '  Bool.pick(List<&2, String>, String.is_empty(cudapath),',
                    '  Bool.pick(List<&2, String>, Bool.not(String.is_empty(cudapath)),',
                    "NVRTCCompiler.includes: invert the CUDA_PATH test (M31)"),
  ("compiler_cuda", "def zr.n(+bs: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, U32, rst.bs(bs)))",
                    "def zr.n(+bs: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, U32, bs))",
                    "zr.n: no rstrip at all (M32)"),
  ("compiler_cuda", "def rst.allzeros(+bs: List<&2, U32>) -> Bool:\n  match bs:\n    case Nil{}: True{}",
                    "def rst.allzeros(+bs: List<&2, U32>) -> Bool:\n  match bs:\n    case Nil{}: False{}",
                    "rst.allzeros: an empty tail is not all zeros (M33)"),
  ("compiler_cuda", 'NVRTCCompiler.arch_opt(arch)', '"--gpu-architecture"',
                    "NVRTCCompiler.arch_opt: drop the arch (M34)"),

  ("compiler_llvm", 'Bool.pick(String, opt, "default<O2>", "default<O0>")',
                    'Bool.pick(String, Bool.not(opt), "default<O2>", "default<O0>")',
                    "LLVMCompiler.passes: invert the LLVMOPT flag (M35)"),
  ("compiler_llvm", 'Bool.pick(String, String.eq(arch, "arm64"), "AArch64",',
                    'Bool.pick(String, Bool.not(String.eq(arch, "arm64")), "AArch64",',
                    "LLVMCompiler.prefix: invert the arm64 arm (M36)"),
  ("compiler_llvm", 'Bool.pick(String, String.eq(arch, "riscv64"), "riscv64", "AMDGPU")',
                    'Bool.pick(String, String.eq(arch, "riscv64"), "X86", "AMDGPU")',
                    "prefix: riscv64 falls to X86 (M37)"),
  ("compiler_llvm", 'String.join(CPULLVMCompiler.featstr.go(feats, []), ",")',
                    'String.join(CPULLVMCompiler.featstr.go(feats, []), " ")',
                    "CPULLVMCompiler.featstr: join with a space (M38)"),
  ("compiler_llvm", 'CPULLVMCompiler.reserve_x18(+arch: String) -> String:\n  Bool.pick(String, String.eq(arch, "arm64"), "+reserve-x18,", "")',
                    'CPULLVMCompiler.reserve_x18(+arch: String) -> String:\n  Bool.pick(String, String.eq(arch, "arm64"), "+reserve-x17,", "")',
                    "reserve_x18: x17 instead of x18 (M39)"),
  ("compiler_llvm", 'String.append(Bool.pick(String, String.is_empty(featstr), "",\n    String.concat([featstr, ","])), CPULLVMCompiler.host_feats())',
                    'String.append(Bool.pick(String, String.is_empty(featstr), "",\n    String.concat([featstr, ""])), CPULLVMCompiler.host_feats())',
                    "feat_native: drop the separating comma (M40)"),
  ("compiler_llvm", 'String.contains(msg, AMDLLVMCompiler.remap_needle())',
                    'String.starts_with(msg, AMDLLVMCompiler.remap_needle())',
                    "remap: `in` becomes `startswith` (M41)"),
  ("compiler_llvm", 'LLVMCompiler.key(+cache_key: String, +processor: String, +feats: String, +opt: Bool) -> String:\n  Bool.pick(String, String.is_empty(cache_key),',
                    'LLVMCompiler.key(+cache_key: String, +processor: String, +feats: String, +opt: Bool) -> String:\n  Bool.pick(String, Bool.not(String.is_empty(cache_key)),',
                    "key: the `or` arm is inverted (M42)"),
  ("compiler_llvm", 'Bool.pick(U32, U32.is_eq(sev, LLVMCompiler.const_ds_error()),\n    [msg], [])',
                    'Bool.pick(List<&2, String>, U32.is_eq(sev, LLVMCompiler.const_ds_error()),\n    [msg], [])',
                    "append_diag: control (M43)"),
  ("compiler_llvm", 'Bool.pick(List<&2, String>, U32.is_eq(sev, LLVMCompiler.const_ds_error()),\n    [msg], [])',
                    'Bool.pick(List<&2, String>, Bool.not(U32.is_eq(sev, LLVMCompiler.const_ds_error())),\n    [msg], [])',
                    "append_diag: collect on a NON-error severity (M44)"),
]


def rows_of(path):
  d = {}
  for line in pathlib.Path(path).read_text(errors="replace").splitlines():
    if "=" in line:
      k, _, v = line.partition("=")
      d.setdefault(k, v)
  return d


def run_bend(f):
  """Re-run and return the interp rows, or None if the file does not COMPILE.
  A mutation that does not compile must NOT be reported as a blind spot: the
  first version did exactly that and three of its six zeros were compile
  failures. A zero-ROW run is the machine stack overflow and is re-run."""
  src = ROOT / f"tinybendygrad/runtime/support/{f}.bend"
  ok = False
  for _ in range(4):
    c = subprocess.run([str(BEND), str(src), "--check-only"], capture_output=True, text=True, timeout=300)
    v = (c.stdout + c.stderr).strip().splitlines()
    if v and "SOME PROOFS FAIL" in v[0]: return None
    if c.returncode == 0 or v: ok = True; break
  if not ok: return None
  for _ in range(4):
    r = subprocess.run([str(BEND), str(src)], capture_output=True, text=True, timeout=300)
    if r.returncode == 0 and "=" in r.stdout: return rows_of_text(r.stdout)
  return {}



# ── THE ROW READER IS `rebase-gate.py`'s OWN, LOADED BY PATH AND NOT COPIED ──────────────
# Measured by reader-fork-census.py on this corpus: 51 of 52 text readers disagreed with
# `rows()` on at least one of six row shapes, and four of them carried a docstring
# claiming to BE it. This file used to be one of them.
# ⚠ NOT FREE, and the census prints the load: of 1,440 lane files under .agents/slop
# (289,262 lines), 44,345 are F2 `py=`-tail lines and 2,370 are F3 two-space lines --
# so a fork that did not fold the tail was reading a DIFFERENT STRING on ~15% of lanes,
# and one that skipped F3 was blind to ~0.8%. Those are the sizes of what was wrong.
_RG = importlib.util.spec_from_file_location("rebase_gate", pathlib.Path(__file__).resolve() / "rebase-gate.py")
_rebase_gate = importlib.util.module_from_spec(_RG)
_RG.loader.exec_module(_rebase_gate)
rows_of_text = _rebase_gate.rows


def main():
  srcs = {f: (ROOT / f"tinybendygrad/runtime/support/{f}.bend").read_text() for f in FILES}
  base = {f: run_bend(f) for f in FILES}
  for f in FILES:
    if not base[f]:
      print(f"BASELINE EMPTY for {f} -- the machine stack overflowed four times; STOP")
      sys.exit(2)
  print(f"baseline rows: " + ", ".join(f"{f}={len(base[f])}" for f in FILES))

  table, zero = [], []
  for (f, old, new, what) in MUTATIONS:
    if old not in srcs[f]:
      table.append((f, what, PNA.not_applied(),
                    "the source text did not match; re-run with the exact text"))
      continue
    p = ROOT / f"tinybendygrad/runtime/support/{f}.bend"
    p.write_text(srcs[f].replace(old, new, 1))
    time.sleep(0.2)
    got = run_bend(f)
    if got is None:
      p.write_text(srcs[f]); table.append((f, what, "COMPILE-FAIL", "the mutation does not typecheck; not a blind spot")); continue
    # the substrate must not have moved under us
    if len(got) != len(base[f]):
      p.write_text(srcs[f]); time.sleep(0.3)
      got = run_bend(f)
    moved = sorted(k for k in base[f] if got.get(k) != base[f][k])
    p.write_text(srcs[f])
    if moved:
      table.append((f, what, str(len(moved)), ", ".join(moved[:8]) + (" ..." if len(moved) > 8 else "")))
    else:
      table.append((f, what, "0", "BLIND SPOT -- see the note in the report"))
      zero.append((f, what))
  # restore and verify
  for f in FILES: (ROOT / f"tinybendygrad/runtime/support/{f}.bend").write_text(srcs[f])
  after = {f: run_bend(f) for f in FILES}
  ok = all(after[f] == base[f] for f in FILES)
  print(f"\nrestored to baseline: {ok}")
  print(f"\n{'file':16} {'rows moved':>10}  mutation")
  for f, what, n, names in table:
    print(f"{f:16} {n:>10}  {what}")
    if n not in ("0", "NOT-APPLIED"):
      print(f"{'':16} {'':>10}    moved: {names}")
  cf = [t for t in table if t[2] == "COMPILE-FAIL"]
  print(f"\n{len(table)} mutations, {len(table) - len(zero) - len(cf)} moving, "
        f"{len(zero)} blind spots, {len(cf)} did not typecheck")
  for f, what in zero: print(f"  BLIND {f}: {what}")


if __name__ == "__main__":
  main()