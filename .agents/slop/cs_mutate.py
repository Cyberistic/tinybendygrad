#!/usr/bin/env python3
"""Mutation table for the four external-compiler backends. MEASURED.

Each mutation is one edit to one .bend file. For each we record the rows that
MOVED, by name. A mutation that moves NOTHING is reported as a blind spot with
a reason -- it is not a claim that the row class is covered.

  row count (absolute, per agent-core: "0 rows" means "not started" OR "broke")
  rows moved, named
"""
import pathlib, re, subprocess, sys
import patch_not_apply as PNA

ROOT = pathlib.Path(__file__).resolve().parents[2]
SLOP = ROOT / ".agents/slop"
BEND = ROOT / "bin/bend"
SUPPORT = ROOT / "tinybendygrad/runtime/support"

# (label, file, old, new)
MUTATIONS = [
  # ---- compiler_amd: the argv builders -------------------------------------
  ("amd.M01 argv1 offload-arch arch dropped", "compiler_amd",
   'String.concat(["--offload-arch=", arch]), C.rocm_include(rocm)',
   'String.concat(["--offload-arch="]), C.rocm_include(rocm)'),
  ("amd.M02 argv2 mcpu arch dropped", "compiler_amd",
   'String.concat(["-mcpu=", arch]), "-O3", "-mllvm"',
   'String.concat(["-mcpu="]), "-O3", "-mllvm"'),
  ("amd.M03 argv1 rocm include path changed", "compiler_amd",
   'String.concat(["-I", rocm, "/include/hip"])',
   'String.concat(["-I", rocm, "/include"] )'),
  ("amd.M04 extra_options spliced BEFORE -o", "compiler_amd",
   '"-o", bc, src], extra)', '"-o"], List.append(&2, String, extra, [bc, src]))'),
  ("amd.M05 extra_options appended before the SOURCE", "compiler_amd",
   '"-o", bc, src], extra)', '"-o", bc], List.append(&2, String, extra, [src]))'),
  ("amd.M06 prog renamed", "compiler_amd", 'def C.prog() -> String: "hipcc"',
   'def C.prog() -> String: "hipcc-5"'),
  ("amd.M07 rocm default changed", "compiler_amd",
   'def C.rocm_default() -> String: "/opt/rocm"', 'def C.rocm_default() -> String: "/opt/rocm6"'),
  ("amd.M08 suffixes reordered", "compiler_amd",
   '[".cpp", ".bc", ".hsaco"]', '[".bc", ".cpp", ".hsaco"]'),
  # ---- compiler_amd: set_options, the load-bearing split --------------------
  ("amd.M09 set_options count +1 (empties dropped)", "compiler_amd",
   'def sp.n(options: String) -> U32: U32.from_nat(List.length(&2, String, String.split(options, \' \')))',
   'def sp.n(options: String) -> U32: U32.add(U32.from_nat(List.length(&2, String, String.split(options, \' \'))), 1)'),
  ("amd.M10 set_options count -1", "compiler_amd",
   'def sp.n(options: String) -> U32: U32.from_nat(List.length(&2, String, String.split(options, \' \')))',
   'def sp.n(options: String) -> U32: U32.sub(U32.from_nat(List.length(&2, String, String.split(options, \' \'))), 1)'),
  ("amd.M11 set_options splits on a NUL-ish char", "compiler_amd",
   "String.split(options, ' ')", "String.split(options, 'x')"),
  # ---- compiler_amd: the .text predicate ------------------------------------
  ("amd.M12 is_asm drops the strip()", "compiler_amd",
   'def C.is_asm(src: String) -> Bool: String.eq(String.trim(C.first_line(src)), ".text")',
   'def C.is_asm(src: String) -> Bool: String.eq(C.first_line(src), ".text")'),
  ("amd.M13 is_asm drops the strip() AND the trim of both ends", "compiler_amd",
   'def C.is_asm(src: String) -> Bool: String.eq(String.trim(C.first_line(src)), ".text")',
   'def C.is_asm(src: String) -> Bool: String.eq(String.trim_end(C.first_line(src)), ".text")'),
  ("amd.M14 is_asm compares a prefix", "compiler_amd",
   'def C.is_asm(src: String) -> Bool: String.eq(String.trim(C.first_line(src)), ".text")',
   'def C.is_asm(src: String) -> Bool: String.contains(String.trim(C.first_line(src)), "text")'),
  # ---- compiler_amd: the cache keys and the messages ------------------------
  ("amd.M15 hip_key loses the prefix", "compiler_amd",
   'def C.hip_key(arch: String) -> String: String.concat(["compile_hip_", arch])',
   'def C.hip_key(arch: String) -> String: arch'),
  ("amd.M16 hipcc_key drops the _nohipcc suffix", "compiler_amd",
   'Bool.pick(String, nohipcc, "_nohipcc", "")', 'Bool.pick(String, nohipcc, "", "")'),
  ("amd.M17 check() message drops the status", "compiler_amd",
   'String.concat(["comgr fail ", U32.show(status), ", ", msg])',
   'String.concat(["comgr fail, ", msg])'),
  ("amd.M18 check() treats 0 as a failure", "compiler_amd",
   'Bool.pick(String, U32.is_eq(status, 0), "",', 'Bool.pick(String, True{}, "",'),
  ("amd.M19 CompileError prefixes its message", "compiler_amd",
   'def C.compile_error(m: String) -> String: m', 'def C.compile_error(m: String) -> String: String.concat(["CompileError: ", m])'),
  # ---- compiler_amd: the option list and the actions ------------------------
  ("amd.M20 one option dropped from the 19", "compiler_amd",
   '"-std=c++14", "-nogpuinc", "-Wno-gnu-line-marker", "-Wno-missing-prototypes",\n    String.concat(["--offload-arch=", arch])',
   '"-std=c++14", "-nogpuinc", "-Wno-gnu-line-marker",\n    String.concat(["--offload-arch=", arch])'),
  ("amd.M21 the codegen option string loses -mllvm", "compiler_amd",
   'def h.opt_codegen() -> String: "-O3 -mllvm -amdgpu-internalize-symbols"',
   'def h.opt_codegen() -> String: "-O3 -amdgpu-internalize-symbols"'),
  ("amd.M22 the ISA name loses its prefix", "compiler_amd",
   'def h.isa(arch: String) -> String: String.append("amdgcn-amd-amdhsa--", arch)',
   'def h.isa(arch: String) -> String: String.append("amdgcn-amd-amdhsa", arch)'),
  ("amd.M23 the asm data name loses its suffix", "compiler_amd",
   'def h.dataname(asm: Bool) -> String: Bool.pick(String, asm, "<null>.s", "<null>")',
   'def h.dataname(asm: Bool) -> String: Bool.pick(String, asm, "<null>", "<null>")'),
  ("amd.M24 hiplang answers 3 for both versions", "compiler_amd",
   'Bool.pick(U32, Bool.and(U32.is_gt(major, 2), True{}), 3, 4)', 'Bool.pick(U32, True{}, 3, 4)'),
  ("amd.M25 a comgr enum value changed", "compiler_amd",
   'def A.act_compile() -> U32: 15', 'def A.act_compile() -> U32: 16'),
  ("amd.M26 gd calls count", "compiler_amd", 'def gd.calls() -> U32: 4', 'def gd.calls() -> U32: 5'),
  ("amd.M27 the asm trace inserts the codegen action", "compiler_amd",
   'Tr.put("amd_comgr_do_action", U32.show(h.act_link_name()), s9)',
   'Tr.put("amd_comgr_action_info_set_option_list", "0", s9)'),
  # ---- compiler_mesa: warps_per_sm ------------------------------------------
  ("mesa.M01 warps: sm_86 drops out of the set", "compiler_mesa",
   'Bool.or(Bool.or(String.eq(arch, "sm_86"), String.eq(arch, "sm_87")),',
   'Bool.or(Bool.or(String.eq(arch, "sm_XX"), String.eq(arch, "sm_87")),'),
  ("mesa.M02 warps: sm_120 drops out of the set", "compiler_mesa",
   'Bool.or(String.eq(arch, "sm_89"), String.eq(arch, "sm_120")))',
   'Bool.or(String.eq(arch, "sm_89"), String.eq(arch, "sm_121")))'),
  ("mesa.M03 warps: the set becomes a PREFIX test", "compiler_mesa",
   'def w.warps_raw(+arch: String) -> U32: Bool.pick(U32, w.is48(arch), 48, 64)',
   'def w.warps_raw(+arch: String) -> U32: Bool.pick(U32, String.starts_with(arch, "sm_8"), 48, 64)'),
  ("mesa.M04 warps: 48 and 64 swapped", "compiler_mesa",
   'def w.warps_raw(+arch: String) -> U32: Bool.pick(U32, w.is48(arch), 48, 64)',
   'def w.warps_raw(+arch: String) -> U32: Bool.pick(U32, w.is48(arch), 64, 48)'),
  # ---- compiler_mesa: the formatters ----------------------------------------
  ("mesa.M05 hex: the digit offset for a-f", "compiler_mesa",
   "Bool.pick(U32, U32.is_gt(d, 9), 39, 0)", "Bool.pick(U32, U32.is_gt(d, 9), 49, 0)"),
  ("mesa.M06 hex: pair shifts by 3", "compiler_mesa",
   "def hx.pair(+b: U32) -> String:\n  String.from_list([hx.digit(U32.shrn(b, 4n)), hx.digit(U32.and(b, 15))])",
   "def hx.pair(+b: U32) -> String:\n  String.from_list([hx.digit(U32.shrn(b, 3n)), hx.digit(U32.and(b, 7))])"),
  ("mesa.M07 hex: upper case A-F", "compiler_mesa",
   "Bool.pick(U32, U32.is_gt(d, 9), 39, 0)", "Bool.pick(U32, U32.is_gt(d, 9), 7, 0)"),
  ("mesa.M08 hex: u32_8 keeps 4 bytes but in LE order", "compiler_mesa",
   "String.append(String.append(hx.pair(U32.shrn(v, 24n)),",
   "String.append(String.append(hx.pair(U32.and(v, 255)),"),
  ("mesa.M09 decimal: the padding is one short", "compiler_mesa",
   "Bool.pick(String, Nat.is_lt(len, U32.to_nat(w)),",
   "Bool.pick(String, Nat.is_lt(len, U32.to_nat(U32.add(w, 1))),"),
  ("mesa.M10 decimal: pad with the digit, not '0'", "compiler_mesa",
   'case 1n+p: String.append(dc.zeros(p), "0")', 'case 1n+p: String.append(dc.zeros(p), "1")'),
  ("mesa.M11 decimal: width is off by one", "compiler_mesa",
   "def dc.fixed(w: U32, +n: U32) -> String: dc.fixed.of(String.length(U32.show(n)), w, U32.show(n))",
   "def dc.fixed(w: U32, +n: U32) -> String: dc.fixed.of(String.length(U32.show(n)), U32.add(w, 1), U32.show(n))"),
  # ---- compiler_mesa: the disas line ---------------------------------------
  ("mesa.M12 line: the two halves swapped", "compiler_mesa",
   'dc.fixed(4, n), " [", hx.u32_8(instr_hi), "_", hx.u32_8(instr_lo)',
   'dc.fixed(4, n), " [", hx.u32_8(instr_lo), "_", hx.u32_8(instr_hi)'),
  ("mesa.M13 line: the trailing space dropped", "compiler_mesa",
   'hx.u32_8(instr_lo), "] "])', 'hx.u32_8(instr_lo), "]")'),
  ("mesa.M41 data64 swaps hi and lo", "compiler_mesa",
   "def da.data64(hi: U32, lo: U32) -> List<&2, U32>: [hi, lo]",
   "def da.data64(hi: U32, lo: U32) -> List<&2, U32>: [lo, hi]"),
  ("mesa.M14 line: width 3 not 4", "compiler_mesa",
   'String.concat([dc.fixed(4, n), " [",', 'String.concat([dc.fixed(3, n), " [",'),
  # ---- compiler_mesa: arch[3:] and the dev info -----------------------------
  ("mesa.M15 a3 drops 2 characters not 3", "compiler_mesa",
   "String.drop(arch, 3n)", "String.drop(arch, 2n)"),
  ("mesa.M16 a3 read multiplies by 8", "compiler_mesa",
   "Nat.add(Nat.mul(acc, 10n), U32.to_nat(U32.sub(Char.to_u32(h), 48)))",
   "Nat.add(Nat.mul(acc, 8n), U32.to_nat(U32.sub(Char.to_u32(h), 48)))"),
  ("mesa.M17 nak.dev warps 0/1 instead of 48/64", "compiler_mesa",
   "def nak.warps(+arch: String) -> U32: Bool.pick(U32, w.is48(arch), 48, 64)",
   "def nak.warps(+arch: String) -> U32: w.warps(arch)"),
  ("mesa.M18 the chip id off by one", "compiler_mesa",
   "def ir3.chip_id() -> U32: 100859905", "def ir3.chip_id() -> U32: 100859906"),
  ("mesa.M19 the a630 assert accepts any arch", "compiler_mesa",
   'def ir3.arch_ok(+arch: String) -> Bool: String.eq(ir3.head.of(String.split(arch, \',\')), "a630")',
   'def ir3.arch_ok(+arch: String) -> Bool: String.eq(ir3.head.of(String.split(arch, \',\')), "a63")'),
  ("mesa.M20 num_uavs is a difference", "compiler_mesa",
   "def ir3.num_uavs(ssbos: U32, images: U32) -> U32: U32.add(ssbos, images)",
   "def ir3.num_uavs(ssbos: U32, images: U32) -> U32: U32.sub(ssbos, images)"),
  ("mesa.M21 num_uavs counts only the images", "compiler_mesa",
   "def ir3.num_uavs(ssbos: U32, images: U32) -> U32: U32.add(ssbos, images)",
   "def ir3.num_uavs(ssbos: U32, images: U32) -> U32: images"),
  # ---- compiler_mesa: unpack_lib, THE HEADLINE ------------------------------
  ("mesa.M22 ul.head drops the const_state offset", "compiler_mesa",
   "def ul.head(variant: U32, const_state: U32) -> U32: U32.add(variant, const_state)",
   "def ul.head(variant: U32, const_state: U32) -> U32: variant"),
  ("mesa.M23 ul.head drops the variant offset", "compiler_mesa",
   "def ul.head(variant: U32, const_state: U32) -> U32: U32.add(variant, const_state)",
   "def ul.head(variant: U32, const_state: U32) -> U32: const_state"),
  ("mesa.M24 ul.imm count*4 becomes count*2", "compiler_mesa",
   "def ul.imm(variant: U32, const_state: U32, +count: U32) -> U32: U32.mul(count, 4)",
   "def ul.imm(variant: U32, const_state: U32, +count: U32) -> U32: U32.mul(count, 2)"),
  ("mesa.M25 ul.imm count*4 becomes count", "compiler_mesa",
   "def ul.imm(variant: U32, const_state: U32, +count: U32) -> U32: U32.mul(count, 4)",
   "def ul.imm(variant: U32, const_state: U32, +count: U32) -> U32: count"),
  ("mesa.M26 ul.total adds head TWICE", "compiler_mesa",
   "U32.add(ul.head(variant, const_state), U32.add(U32.mul(count, 4), info_size))",
   "U32.add(ul.head(variant, const_state), U32.add(ul.head(variant, const_state), U32.add(U32.mul(count, 4), info_size)))"),
  ("mesa.M27 ul.asm_len is the head, not total-minus-head", "compiler_mesa",
   "U32.sub(ul.total(variant, const_state, count, info_size), ul.head(variant, const_state))",
   "ul.head(variant, const_state)"),
  ("mesa.M28 ul.split_point forgets the head", "compiler_mesa",
   "U32.add(ul.head(variant, const_state), U32.mul(count, 4))", "U32.mul(count, 4)"),
  ("mesa.M29 ret_parts multiplies by 8", "compiler_mesa",
   "[variant, const_state, U32.mul(count, 4), info_size]", "[variant, const_state, U32.mul(count, 8), info_size]"),
  # ---- compiler_mesa: the external commands ---------------------------------
  ("mesa.M30 nvdisasm loses the -b flag", "compiler_mesa",
   '["nvdisasm", "-b", String.concat(["SM", a3.drop3(arch)]), nv.path(tmp, digest)]',
   '["nvdisasm", String.concat(["-bSM", a3.drop3(arch)]), nv.path(tmp, digest)]'),
  ("mesa.M31 nvdisasm drops the -b flag entirely", "compiler_mesa",
   '["nvdisasm", "-b", String.concat(["SM", a3.drop3(arch)]), nv.path(tmp, digest)]',
   '["nvdisasm", String.concat(["SM", a3.drop3(arch)]), nv.path(tmp, digest)]'),
  ("mesa.M32 nvdisasm drops the SM prefix", "compiler_mesa",
   'String.concat(["SM", a3.drop3(arch)])', 'a3.drop3(arch)'),
  ("mesa.M33 the temp path loses its directory", "compiler_mesa",
   'String.concat([tmp, "/tinynak_", digest])', 'String.concat(["tinynak_", digest])'),
  ("mesa.M34 objdump loses the -d flag", "compiler_mesa",
   'def dso.cmd(+tmp: String) -> List<&2, String>: [dso.tool(), "-d", String.concat([tmp, "/", dso.file()])]',
   'def dso.cmd(+tmp: String) -> List<&2, String>: [dso.tool(), String.concat([tmp, "/", dso.file()])]'),
  ("mesa.M35 objdump renames kernel.o", "compiler_mesa",
   'def dso.file() -> String: "kernel.o"', 'def dso.file() -> String: "kernel"'),
  # ---- compiler_mesa: lvp, lp_type, blob ------------------------------------
  ("mesa.M36 lvp arch_n +1", "compiler_mesa",
   "def lvp.arch_n(+arch: String) -> U32: U32.from_nat(List.length(&2, String, lvp.archs(arch)))",
   "def lvp.arch_n(+arch: String) -> U32: U32.add(U32.from_nat(List.length(&2, String, lvp.archs(arch))), 1)"),
  ("mesa.M37 lp_type width 64", "compiler_mesa", "def lpt.width() -> U32: 32", "def lpt.width() -> U32: 64"),
  ("mesa.M38 lp_type length 8", "compiler_mesa", "def lpt.length() -> U32: 4", "def lpt.length() -> U32: 8"),
  ("mesa.M39 b64 padding ignores the second '='", "compiler_mesa",
   'Bool.pick(U32, de.b64_pad2(encoded), 2, Bool.pick(U32, de.b64_pad1(encoded), 1, 0))',
   'Bool.pick(U32, False{}, 2, Bool.pick(U32, de.b64_pad1(encoded), 1, 0))'),
  ("mesa.M40 b64 bytes forget the padding", "compiler_mesa",
   "def de.b64_bytes.of(+n: U32, +pad: U32) -> U32: U32.sub(U32.mul(U32.div(n, 4), 3), pad)",
   "def de.b64_bytes.of(+n: U32, +pad: U32) -> U32: U32.mul(U32.div(n, 4), 3)"),
  # ---- compiler_qcom: the read and the slice --------------------------------
  ("qcom.M01 read big-endian", "compiler_qcom",
   "def q.read(+b0: U32, +b1: U32, +b2: U32, +b3: U32) -> U32:\n  U32.or(U32.or(b0, U32.shln(b1, 8n)), U32.or(U32.shln(b2, 16n), U32.shln(b3, 24n)))",
   "def q.read(+b0: U32, +b1: U32, +b2: U32, +b3: U32) -> U32:\n  U32.or(U32.or(U32.shln(b0, 24n), U32.shln(b1, 16n)), U32.or(U32.shln(b2, 8n), b3))"),
  ("qcom.M02 read shifts by 4", "compiler_qcom",
   "def q.read(+b0: U32, +b1: U32, +b2: U32, +b3: U32) -> U32:\n  U32.or(U32.or(b0, U32.shln(b1, 8n)), U32.or(U32.shln(b2, 16n), U32.shln(b3, 24n)))",
   "def q.read(+b0: U32, +b1: U32, +b2: U32, +b3: U32) -> U32:\n  U32.or(U32.or(b0, U32.shln(b1, 4n)), U32.or(U32.shln(b2, 8n), U32.shln(b3, 12n)))"),
  ("qcom.M03 read_ok uses > not >=", "compiler_qcom",
   "def q.read_ok(+len: U32, +off: U32) -> Bool: U32.is_ge(U32.sub(len, off), 4)",
   "def q.read_ok(+len: U32, +off: U32) -> Bool: U32.is_gt(U32.sub(len, off), 4)"),
  ("qcom.M04 the two positions collapse to one", "compiler_qcom",
   "def q.len_pos() -> U32: 256", "def q.len_pos() -> U32: 192"),
  ("qcom.M05 slice_end forgets to add the offset", "compiler_qcom",
   "U32.add(q.read_at(bs, q.off_pos()), q.read_at(bs, q.len_pos()))",
   "q.read_at(bs, q.len_pos())"),
  ("qcom.M06 slice_len is the offset, not the length", "compiler_qcom",
   "def q.slice_len(+n: U32, +bs: List<&2, U32>) -> U32: q.read_at(bs, q.len_pos())",
   "def q.slice_len(+n: U32, +bs: List<&2, U32>) -> U32: q.read_at(bs, q.off_pos())"),
  ("qcom.M07 the a630 assert accepts a63", "compiler_qcom",
   'def q.arch_ok(+arch: String) -> Bool: String.eq(q.head.of(String.split(arch, \',\')), "a630")',
   'def q.arch_ok(+arch: String) -> Bool: String.eq(q.head.of(String.split(arch, \',\')), "a63")'),
  ("qcom.M08 the chip id", "compiler_qcom", "def q.chip_id() -> U32: 100859905", "def q.chip_id() -> U32: 100859904"),
  ("qcom.M09 the cache key prefix", "compiler_qcom",
   'def q.key(+arch: String) -> String: String.concat(["compile_qcomcl_", arch])',
   'def q.key(+arch: String) -> String: String.concat(["compile_qcom_", arch])'),
  # ---- compiler_qcom: the two command strings -------------------------------
  ("qcom.M10 qemu drops -L", "compiler_qcom",
   'String.join([qemu, "-cpu", "max,pauth=off", "-L", fs, String.concat([fs, "/usr/bin/python3"])], " ")',
   'String.join([qemu, "-cpu", "max,pauth=off", fs, String.concat([fs, "/usr/bin/python3"])], " ")'),
  ("qcom.M11 qemu drops pauth=off", "compiler_qcom",
   'String.join([qemu, "-cpu", "max,pauth=off", "-L", fs,', 'String.join([qemu, "-cpu", "max", "-L", fs,'),
  ("qcom.M12 docker drops the second -v mount", "compiler_qcom",
   '"-v", String.concat([root, ":", root]),\n    "-e", String.concat(["PYTHONPATH=", root]),',
   '"-e", String.concat(["PYTHONPATH=", root]),'),
  ("qcom.M13 docker drops PYTHONPATH", "compiler_qcom",
   '"-e", String.concat(["PYTHONPATH=", root]),\n    "-e", "QEMU_CPU=max,pauth=off"', '"-e", "QEMU_CPU=max,pauth=off"'),
  ("qcom.M14 docker drops the platform", "compiler_qcom",
   '"docker", "run", "--rm", "-i", "--platform", "linux/aarch64",\n    "-v"', '"docker", "run", "--rm", "-i",\n    "-v"'),
  ("qcom.M15 docker mounts the fs read-write as /usr", "compiler_qcom",
   'String.join(["docker", "run", "--rm", "-i", "--platform", "linux/aarch64",\n    "-v", String.concat([fs, "/usr:/usr"]),',
   'String.join(["docker", "run", "--rm", "-i", "--platform", "linux/aarch64",\n    "-v", String.concat([fs, "/usr"]),'),
  # ---- compiler_qcom: checked() --------------------------------------------
  ("qcom.M16 fails() ignores the error code", "compiler_qcom",
   "Bool.or(Bool.not(handle), U32.is_ne(error_code, 0))", "Bool.not(handle)"),
  ("qcom.M17 msg() always appends the log", "compiler_qcom",
   'Bool.pick(String, Bool.not(handle), "QCOM Compilation Error",\n    String.concat(["QCOM Compilation Error: ", build_log]))',
   'String.concat(["QCOM Compilation Error: ", build_log])'),
  ("qcom.M18 msg() drops the colon", "compiler_qcom",
   'String.concat(["QCOM Compilation Error: ", build_log])', 'String.concat(["QCOM Compilation Error", build_log])'),
  ("qcom.M19 the linked handle id", "compiler_qcom", "def q.handle_linked() -> U32: 2", "def q.handle_linked() -> U32: 1"),
  # ---- compiler_qcom: the argument lists ------------------------------------
  ("qcom.M20 the two zeros become one", "compiler_qcom",
   "[chip_id, 64, 0, 0, 0, 0, q.src_str(), 0]", "[chip_id, 64, 0, 0, q.src_str(), 0]"),
  ("qcom.M21 CL_SRC_STR is 0", "compiler_qcom", "def q.src_str() -> U32: 1", "def q.src_str() -> U32: 0"),
  ("qcom.M22 the link count is 1 -> 0", "compiler_qcom", "def q.link_args(+chip_id: U32) -> List<&2, U32>: [chip_id, 64, 1]",
   "def q.link_args(+chip_id: U32) -> List<&2, U32>: [chip_id, 64, 0]"),
  ("qcom.M23 CL_MODE_64BIT", "compiler_qcom", "def q.mode() -> U32: 64", "def q.mode() -> U32: 32"),
  # ---- compileserver: the frame --------------------------------------------
  ("cs.M01 pack big-endian", "compileserver",
   "[U32.and(v, 255), U32.and(U32.shrn(v, 8n), 255),\n   U32.and(U32.shrn(v, 16n), 255), U32.shrn(v, 24n)]",
   "[U32.shrn(v, 24n), U32.and(U32.shrn(v, 16n), 255), U32.and(U32.shrn(v, 8n), 255), U32.and(v, 255)]"),
  ("cs.M02 pack shifts by 4", "compileserver",
   "[U32.and(v, 255), U32.and(U32.shrn(v, 8n), 255),\n   U32.and(U32.shrn(v, 16n), 255), U32.shrn(v, 24n)]",
   "[U32.and(v, 15), U32.and(U32.shrn(v, 4n), 15),\n   U32.and(U32.shrn(v, 8n), 15), U32.shrn(v, 12n)]"),
  ("cs.M03 unpack is big-endian", "compileserver",
   "def cs.unpack(+b0: U32, +b1: U32, +b2: U32, +b3: U32) -> U32:\n  U32.or(U32.or(b0, U32.shln(b1, 8n)), U32.or(U32.shln(b2, 16n), U32.shln(b3, 24n)))",
   "def cs.unpack(+b0: U32, +b1: U32, +b2: U32, +b3: U32) -> U32:\n  U32.or(U32.or(U32.shln(b0, 24n), U32.shln(b1, 16n)), U32.or(U32.shln(b2, 8n), b3))"),
  ("cs.M04 the hex digit offset for a-f", "compileserver",
   "def hx2.digit(+d: U32) -> Char:\n  Char.from_u32(U32.add(U32.add(48, Bool.pick(U32, U32.is_gt(d, 9), 39, 0)), d))",
   "def hx2.digit(+d: U32) -> Char:\n  Char.from_u32(U32.add(U32.add(48, Bool.pick(U32, U32.is_gt(d, 9), 49, 0)), d))"),
  ("cs.M05 hex: upper case", "compileserver",
   "Bool.pick(U32, U32.is_gt(d, 9), 39, 0)", "Bool.pick(U32, U32.is_gt(d, 9), 7, 0)"),
  ("cs.M06 the nth-byte ladder inverted", "compileserver",
   "case +h <> t: Bool.pick(U32, Nat.is_eq(n, 0n), h, q.at(t, Nat.sub(n, 1n)))",
   "case +h <> t: Bool.pick(U32, Nat.is_eq(n, 0n), 0, q.at(t, Nat.sub(n, 1n)))"),
  ("cs.M07 the loop head is >= 0", "compileserver",
   "def cs.more(+available: U32) -> Bool: U32.is_gt(available, 0)", "def cs.more(+available: U32) -> Bool: True{}"),
  ("cs.M08 the loop head is always true", "compileserver",
   "def cs.more(+available: U32) -> Bool: U32.is_gt(available, 0)", "def cs.more(+available: U32) -> Bool: False{}"),
  ("cs.M09 on_error keeps the library", "compileserver", "def cs.on_error(+lib: U32) -> U32: 0", "def cs.on_error(+lib: U32) -> U32: lib"),
  ("cs.M10 the argv floor is 2", "compileserver", "def cs.argv_min() -> U32: 3", "def cs.argv_min() -> U32: 2"),
  ("cs.M11 argv_ok is > 3", "compileserver",
   "def cs.argv_ok(+argc: U32) -> Bool: U32.is_ge(argc, 3)", "def cs.argv_ok(+argc: U32) -> Bool: U32.is_gt(argc, 3)"),
  ("cs.M12 the spec arity is 3", "compileserver",
   "def cs.spec_ok(+spec: String) -> Bool: U32.is_eq(cs.spec_n(spec), 2)", "def cs.spec_ok(+spec: String) -> Bool: U32.is_eq(cs.spec_n(spec), 3)"),
  ("cs.M13 the spec splits on '.'", "compileserver",
   "String.split(spec, ':')", "String.split(spec, '.')"),
  ("cs.M14 the usage string", "compileserver",
   'String.concat(["usage: ", argv0, " <compiler> <arch> [<args>]"])',
   'String.concat(["usage: ", argv0, "<compiler> <arch>"])'),
  ("cs.M15 the extra count is argc - 2", "compileserver",
   "def cs.extra_n(+argc: U32) -> U32: U32.sub(argc, 3)", "def cs.extra_n(+argc: U32) -> U32: U32.sub(argc, 2)"),
  ("cs.M16 the frame header is 5 bytes", "compileserver", "def cs.n_needed() -> U32: 4", "def cs.n_needed() -> U32: 5"),
]


def run(path):
  r = subprocess.run([str(BEND), str(path)], capture_output=True, text=True, timeout=300, cwd=str(ROOT))
  out = r.stdout
  if r.returncode != 0 or "SOME PROOFS FAIL" in out:
    return None
  d = {}
  for line in out.splitlines():
    if "=" in line:
      k, _, v = line.partition("=")
      d[k] = v
  return d


def main():
  files = ["compiler_amd", "compiler_mesa", "compiler_qcom", "compileserver"]
  base = {}
  for f in files:
    base[f] = run(SUPPORT / f"{f}.bend")
  if any(v is None for v in base.values()):
    print("BASELINE FAILED -- refusing to report a table over a broken baseline")
    for f, v in base.items():
      if v is None: print(f"  {f} did not run")
    sys.exit(1)
  print(f"baseline rows: " + ", ".join(f"{f}={len(base[f])}" for f in files))
  print(f"total baseline rows: {sum(len(v) for v in base.values())}\n")

  moved_any = zeros = broke = 0
  table = []
  for label, f, old, new in MUTATIONS:
    p = SUPPORT / f"{f}.bend"
    orig = p.read_text()
    if orig.count(old) != 1:
      table.append((label, PNA.not_applied("anchor x%d" % orig.count(old)), []))
      zeros += 1
      continue
    try:
      p.write_text(orig.replace(old, new))
      got = run(p)
    finally:
      p.write_text(orig)
    if got is None:
      table.append((label, "DID NOT COMPILE", []))
      broke += 1
      continue
    diff = [k for k in sorted(set(base[f]) | set(got))
            if base[f].get(k) != got.get(k)]
    if diff:
      moved_any += 1
      table.append((label, f"{len(diff)} rows", diff))
    else:
      zeros += 1
      table.append((label, "0 rows", []))

  w = max(len(t[0]) for t in table)
  for label, res, diff in table:
    print(f"{label.ljust(w)}  {res}")
    if diff and len(diff) <= 8:
      print(f"{' '.ljust(w)}  moved: {', '.join(diff)}")
    elif diff:
      print(f"{' '.ljust(w)}  moved: {', '.join(diff[:6])} ... (+{len(diff) - 6})")
  print(f"\n{moved_any} mutations move rows, {zeros} move nothing, {broke} do not compile")
  (SLOP / "cs_mutation_table.txt").write_text("\n".join(
    f"{l}\t{r}\t{'|'.join(d)}" for l, r, d in table) + "\n")


if __name__ == "__main__":
  main()