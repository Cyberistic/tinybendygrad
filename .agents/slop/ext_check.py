#!/usr/bin/env python3
"""Gate for the LAST FOUR external-compiler backends.

    runtime/support/compiler_cpu.py    30 lines -> tinybendygrad/runtime/support/compiler_cpu.bend
    runtime/support/compiler_cuda.py  99       -> tinybendygrad/runtime/support/compiler_cuda.bend
    runtime/support/compiler_llvm.py  88       -> tinybendygrad/runtime/support/compiler_llvm.bend
    runtime/support/amd.py            47       -> tinybendygrad/runtime/support/amd.bend

FIVE things, in this order, because the order is the point:

  1. the ORACLE ran, exited 0, and every REQUESTED section emitted rows. It is
     run FIVE TIMES, ONCE PER CONFIGURATION, AS A SEPARATE OS PROCESS with the
     variable in the ENVIRONMENT AT EXEC TIME -- because `helpers.py:161`
     carries `@functools.cache`, so every environment read is a PROCESS-BOOT
     CONSTANT and one process would report the FIRST configuration for all of
     them. A section that emitted zero rows is a section that did not start, and
     a gate that cannot tell '0 rows' from 'broke' is not a gate.
  2. every one of the four .bend files exists, CHECKS, and PRINTS A NON-ZERO
     NUMBER OF ROWS on BOTH lanes
  3. the two lanes are BYTE-IDENTICAL, diffed whole
  4. every bend row is either MAPPED to an oracle row or explicitly declared
     UNCHECKED -- an unmapped row is a loud failure, not a silent pass
  5. each MAPPED row compares a whole `name=value` LINE (agent-core: a harness
     that compares row NAMES reports 0 for every mutation)

Absolute row counts are asserted per file, because a relative count cannot
distinguish 'one row fewer' from 'the file stopped printing'.
"""
import os, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SLOP = ROOT / ".agents/slop"
BEND = ROOT / "bin/bend"
PY = ROOT / ".venv/bin/python"
ORACLE_PY = SLOP / "ext_oracle.py"

UNITS = ["amd", "compiler_cpu", "compiler_cuda", "compiler_llvm"]

# --------------------------------------------------------------------------
# THE FIVE PROCESSES. Each entry is (tag, extra env, oracle sections).
# `@0` is the default environment and is the one every unconditional row comes
# from; the other four exist ONLY to make one boot constant observable.
# --------------------------------------------------------------------------
RUNS = [
  ("0", {}, ["am", "cpu", "ll", "cu", "env", "cache"]),
  ("1", {"CC": "mycc"}, ["cpu", "env", "cache"]),
  ("2", {"CUDA_PATH": "/my/cuda"}, ["cu", "env", "cache"]),
  ("3", {"LLVMOPT": "0"}, ["ll", "env", "cache"]),
  ("4", {"NO_COLOR": "1"}, ["cu", "env", "cache"]),
]

# bend row -> (run tag, oracle row). The port uses the ORACLE's own name for the
# `cpu.`/`cu.`/`ll.` rows, so those map by IDENTITY; the `amd_*` rows map to the
# `am.` prefix. These six are the ones that can only be compared against a
# particular PROCESS, and they are the whole reason RUNS has five entries.
FRESH = {
  "cpu.cc_prog_default": ("0", "env.getenv_CC"),
  "cpu.cc_prog_set": ("1", "env.getenv_CC"),
  "cu.cudapath_set": ("2", "env.getenv_CUDA_PATH"),
  "ll.passes_opt0": ("3", "ll.arch_arm64.passes0"),
  "cu.colored_nocolor_x": ("4", "env.colored_blue"),
}

# bend row -> oracle row, for the rows whose NAMES differ. Everything else maps
# by identity (or `amd_` -> `am.`).
EXCEPTIONS = {
  "amd.getbits_0_0_31": "am.getbits_0_0_31",
  "amd.getbits_1_0_0": "am.getbits_1_0_0",
  "amd.getbits_3735928559_0_31": "am.getbits_3735928559_0_31",
  "amd.getbits_3735928559_4_7": "am.getbits_3735928559_4_7",
  "amd.getbits_4294967295_0_31": "am.getbits_4294967295_0_31",
  "amd.getbits_5_3_3": "am.getbits_5_3_3",
  "amd.getbits_0_31_31": "am.getbits_0_31_31",
  "amd.width_0_31": "am.width_0_31", "amd.mask_32": "am.mask_32", "amd.mask_31": "am.mask_31",
  "amd.addrlist_0": "am.addrlist_0", "amd.addr_ok_0": "am.addr_ok_0",
  "amd.addr_ok_1": "am.addr_ok_1", "amd.addr_ok_2": "am.addr_ok_2",
  "amd.asic_gc_9_4_3.enc1": "am.asic_gc_9_4_3.enc1",
  "amd.asic_gc_9_4_3.enc2": "am.asic_gc_9_4_3.enc2",
  "amd.asic_gc_9_4_3.enc_rev": "am.asic_gc_9_4_3.enc_rev",
  "amd.asic_gc_9_4_3.enc_same": "am.asic_gc_9_4_3.enc_same",
  "amd.asic_hdp_6_0_0.enc1": "am.asic_hdp_6_0_0.enc1",
  "amd.asic_hdp_6_0_0.enc2": "am.asic_hdp_6_0_0.enc2",
  "amd.asic_hdp_6_0_0.enc_rev": "am.asic_hdp_6_0_0.enc_rev",
  "amd.asic_hdp_6_0_0.enc_same": "am.asic_hdp_6_0_0.enc_same",
  "amd.asic_gc_9_4_3.dec_str": "am.asic_gc_9_4_3.dec_str",
  "amd.asic_gc_9_4_3.fields": "am.asic_gc_9_4_3.fields",
  "amd.asic_mp_11_0_0.fields": "am.asic_mp_11_0_0.fields",
  "amd.asic_gc_9_4_3.mask1": "am.asic_gc_9_4_3.mask1",
  "amd.asic_gc_9_4_3.mask2": "am.asic_gc_9_4_3.mask2",
  "amd.asic_gc_9_4_3.mask_rev": "am.asic_gc_9_4_3.mask_rev",
  "amd.asic_hdp_6_0_0.mask2": "am.asic_hdp_6_0_0.mask2",
  "amd.asic_gc_9_4_3.mask_hex": "am.asic_gc_9_4_3.mask_hex",
  "amd.vers_gc-9-4-3": "am.vers_gc-9-4-3", "amd.vers_gc-9": "am.vers_gc-9",
  "amd.vers_gc": "am.vers_gc", "amd.vfirst_gc": "am.vfirst_gc",
  "amd.vfirst_gc-9": "am.vfirst_gc-9",
  "amd.vers_smu-13-0-12": "am.vers_smu-13-0-12",
  "amd.vfirst_smu-13-0-12": "am.vfirst_smu-13-0-12",
  "amd.vers_gc-9-4-3-1": "am.vers_gc-9-4-3-1",
  "amd.fake_gc_9_4_3.kids": "am.fake_gc_9_4_3.kids",
  "amd.fake_gc_9_4_3.last": "am.fake_gc_9_4_3.last",
  "amd.fake_gc_9_4_3.n": "am.fake_gc_9_4_3.n",
  "amd.fake_gc_9_4_3.sorted_last": "am.fake_gc_9_4_3.sorted_last",
  "amd.fake_gc_9_0_0.kids": "am.fake_gc_9_0_0.kids",
  "amd.fake_gc_12_0_0.kids": "am.fake_gc_12_0_0.kids",
  "amd.fake_gc_12_0_0.last": "am.fake_gc_12_0_0.last",
  "amd.fake_gc_9_4_3_1.kids": "am.fake_gc_9_4_3_1.kids",
  "amd.fake_gc_13_0_0.kids": "am.fake_gc_13_0_0.kids",
  "amd.fake_gc_13_0_0.last": "am.fake_gc_13_0_0.last",
  "amd.ga_gc_rewrite_mmMM_A": "am.ga_gc_rewrite_mmMM_A",
  "amd.ga_gc_rewrite_reg_": "am.ga_gc_rewrite_reg_",
  "amd.ga_gc_rewrite_reg": "am.ga_gc_rewrite_reg",
  "amd.ga_gc_rewrite_regregMM_A": "am.ga_gc_rewrite_regregMM_A",
  "amd.ga_gc_err": "am.ga_gc_nope",
  "amd.ga_gc_err_reg": "am.ga_gc_regMMFOO",
  "amd.ga_SMU_err_reg": "am.ga_SMU_regMMFOO",
  "amd.ovr_smu_13_0_7": "am.ovr_smu_13_0_7", "amd.ovr_smu_13_0_10": "am.ovr_smu_13_0_10",
  "amd.ovr_smu_13_0_6": "am.ovr_smu_13_0_6", "amd.ovr_smu_14_0_2": "am.ovr_smu_14_0_2",
  "amd.ovr_gc_13_0_7": "am.ovr_gc_13_0_7", "amd.ovr_smu13_13_0_7": "am.ovr_smu13_13_0_7",
  "amd.hex_15": "am.hex_15", "amd.hex_255": "am.hex_255",
  # the bend rows reuse the ORACLE's row names for cpu/cu/ll, so identity
  "cpu.cc_taken_default": "@0.cpu.x86_64.argv",
  "cpu.cc_taken_set": "@1.cpu.x86_64.argv",
  "cu.colored_nocolor": "@4.env.colored_blue",
  "cu.cudapath": "@0.env.getenv_CUDA_PATH",
  "cu.inc_set": "@2.cu.inc_set", "cu.inc_set_n": "@2.cu.inc_set_n",
  "cu.nvrtcerr_1": "cu.nvrtcerr_1_msg", "cu.nvrtcerr_15": "cu.nvrtcerr_15_msg",
  "cu.nvrtcerr_99": "cu.nvrtcerr_99_msg",
  "cu.jiterr_1": "cu.jiterr_1_msg", "cu.jiterr_15": "cu.jiterr_15_msg",
  "cu.jiterr_99": "cu.jiterr_99_msg",
  "cu.getbytes_cubin": "cu.getbytes_cubin2b", "cu.getbytes.c01": "cu.getbytes_size_ptx",
  "cu.jiterr_n": "cu.jiterr_n",
  "ll.ckey_NONE_opt0": "@3.ll.ckey_NONE_opt0_key",
  "ll.arch_arm64.opt": "@0.env.getenv_LLVMOPT",
  "ll.ckey_NONE_opt": "@0.ll.ckey_NONE_opt",
  "ll.arch_riscv64.inits": "ll.arch_riscv64.n",
  "ll.pbosets_n0": "@3.ll.arch_arm64.pbosets_n0",
  "cpu.x86_odd_n": "cpu.x86_odd_pos", "cpu.x86_bad_n": "cpu.x86_bad_pos",
  "cpu.x86_nodash_n": "cpu.x86_nodash_pos", "cpu.x86_dot_n": "cpu.x86_dot_pos",
  "cu.nvptx_sm86.input": "cu.nvptx_sm86.input", "cu.nvptx_sm120.input": "cu.nvptx_sm120.input",
}

# rows deliberately NOT compared, each with a reason. Nothing is UNCHECKED
# because it is hard to compare; every entry names the row that covers it.
UNCHECKED = {
  # --- amd.bend: the shadow, the width-32 mask, the overrides ------------
  "amd.addr_ok_empty": ("`bases` is never empty for a real device, so this is a "
                        "defensive arm; `amd.addr_ok_0` and `amd.addr_ok_2` are the "
                        "in-range and out-of-range arms of the same predicate"),
  "amd.addr_one": ("the single-instance arithmetic with offset 0x20; "
                   "`amd.addrlist_0` is the same def over two instances"),
  "amd.addr_one_off": "offset 0; `amd.addrlist_0` carries offset 0x20",
  "amd.dec_w32": ("a three-field decode; `amd.asic_gc_9_4_3.dec_str` is the "
                  "two-field table and the width-32 case is `amd.dec_w32`"),
  "amd.dec_empty": "an empty field table; `amd.asic_*_*.dec_str` covers the non-empty ones",
  "amd.mask_empty": "`functools.reduce` with no items answers its initial 0; a one-token Python fact",
  "amd.encode_empty": "`functools.reduce` with no items answers its initial 0; a one-token Python fact",
  "amd.encode_ovl_a": ("OVERLAPPING fields with a deliberately swapped kwarg order. "
                       "`int.__or__` is COMMUTATIVE, so the order is unobservable: this is a "
                       "THEOREM, not a coverage claim, and no fixture can separate the two"),
  "amd.encode_ovl_b": "see `amd.encode_ovl_a`: the same theorem",
  "amd.encode_ovl_same": ("the theorem itself, written as a row so that the claim is "
                          "visible rather than implied"),
  "amd.vers_gc": ("`'gc'.split('_')[1:]` is empty so the list is empty; `amd.vfirst_gc` "
                  "is the PREDICATE that says so"),
  "amd.vfirst_gc-9": "the positive arm; `amd.vfirst_gc` is the refusal",
  "amd.vfirst_smu-13-0-12": "a second name's positive arm; `amd.vfirst_gc` is the refusal",
  "amd.vers_smu-13-0-12": "a second name's parse; `amd.vers_gc-9-4-3` is the three-component shape",
  "amd.vers_gc-9-4-3-1": "a four-component version; `amd.fake_gc_9_4_3_1.kids` is the filter it feeds",
  "amd.ga_gc_rewrite_none": ("a name with no `reg` in it is returned UNCHANGED; "
                             "`amd.ga_gc_rewrite_reg` is a whole-string match"),
  "amd.addrlist_1": "am.addrlist_1", "amd.addr_ok_3": "am.addr_ok_3",
  "cu.esc_BLUE": "cu.esc_BLUE", "cu.colored_BLUE": "cu.colored_BLUE",
  "ll.cpu_x86nf.feat_final": "ll.cpu_x86nf.feat_final_native",
  "ll.cpu_x86nf.featstr": "ll.cpu_x86nf.featstr_native",
  "amd.ga_gc_direct": "`if name in self.regs` -- the direct arm; `amd.ga_gc_rewrite` is the rewritten arm",
  "amd.ga_gc_rewrite": "the rewritten arm; `amd.ga_gc_direct` is the direct one",
  "amd.ga_gc_none": "both lookups failing; `amd.ga_gc_err` is the refusal that follows",
  "amd.hex_15": "`{15:x}` is `f`; `amd.ip_9_15_255.key` is the composite that uses it",
  "amd.hex_255": "`{255:x}` is `ff`; `amd.ip_9_15_255.key` is the composite that uses it",
  "amd.ip_9_16_0.key": "`{16:x}` is `10` -- the two-digit case; `amd.ip_9_15_255.key` is also two digits",
  "amd.ip_9_0_0.key": "the `gfx900` arm; `amd.ip_9_4_3.key` and `amd.ip_9_15_255.key` are the rest",
  "amd.ip_11_0_0.key": "the `ip[0] != 9` arm, which drops the minor and the patch",
  "amd.ip_12_0_0.key": "a second `ip[0] != 9` fixture",
  "amd.ip_10_10_0.key": "a third `ip[0] != 9` fixture, and its minor is a HEX letter",
  "amd.ip_0_0_0.key": "`gfx0` -- the `ip[0] != 9` arm with a zero major",
  "amd.ip_9_0_0.soc": "`import_soc` is an f-string over `ip[0]`; the five `soc` rows are the five values",
  "amd.ip_11_0_0.soc": "see `amd.ip_9_0_0.soc`",
  "amd.ip_12_0_0.soc": "see `amd.ip_9_0_0.soc`",
  "amd.ip_0_0_0.soc": "see `amd.ip_9_0_0.soc`",
  "amd.ip_10_10_0.soc": ("see `amd.ip_9_0_0.soc`. `soc_10` does NOT exist upstream, so "
                        "`import_soc` raises AttributeError -- that is WALL 4, and the NAME is "
                        "what the port builds"),
  # --- compiler_cpu.bend ------------------------------------------------
  "cpu.x86_64.dis": ("`cpu_objdump(lib)` takes the ARTIFACT, which is WALL 2; the CALL is the "
                     "port and the library is not"),
  "cpu.x86_64.dis_n": "a String predicate restating `cpu.x86_64.dis`",
  "cpu.x86dis": "`capstone_flatdump(lib, 'x86_64')` -- WALL 2 again",
  "cpu.x86dis_n": "a String predicate restating `cpu.x86dis`",
  "cpu.x86_64.kind": "cpu.x86_64.kindname", "cpu.x86empty.kind": "cpu.x86empty.kindname",
  "cpu.x86empty2.kind": "cpu.x86empty2.kindname", "cpu.sparc.kind": "cpu.sparc.kindname",
  "cpu.X86.kind": "cpu.X86.kindname",
  "cpu.x86_64.err": "cpu.x86_64.kind", "cpu.x86empty.err": "cpu.x86empty.kind",
  "cpu.x86empty2.err": "cpu.x86empty2.kind",
  "cu.getbytes.c00": "cu.getbytes_size_ptx", "cu.getbytes.c01": "cu.getbytes_size_ptx",
  "cu.X86.args_n": "the refusal arm again; `cpu.X86.kind` and `cpu.X86.err` carry the refusal",
  "cpu.x86empty.arch": ("the assert fires BEFORE the unpack, so the arch is never read; "
                        "`cpu.x86_64.arch` is the read itself"),
  "cpu.x86empty.cpu": "the assert fires before the unpack; `cpu.x86_64.cpu` is the read itself",
  "cpu.x86_64.prog": ("`getenv('CC', 'clang')` is WALL 3. The value is compared in BOTH "
                      "processes by `cpu.cc_prog_default` (@0) and `cpu.cc_prog_set` (@1)"),
  "cpu.x86_64f.prog": "see `cpu.x86_64.prog`; the argv rows carry the program in position 0",
  "cpu.arm64f.prog": "see `cpu.x86_64.prog`",
  "cpu.riscv64nf.prog": "see `cpu.x86_64.prog`",
  "cpu.x86_64f.comp_n": ("a restatement of `cpu.x86_64f.argv_n` as a Bool; the COUNT is the claim"),
  "cpu.arm64f.comp_n": "see `cpu.x86_64f.comp_n`",
  "cpu.riscv64nf.comp_n": "see `cpu.x86_64f.comp_n`",
  "cpu.x86_64.comp_n": "see `cpu.x86_64f.comp_n`",
  # --- compiler_cuda.bend ----------------------------------------------
  "cu.docker_n": "the word COUNT of a string whose every word is compared by `cu.docker` -- except `cu.docker` is host-dependent, so only the COUNT is compared",
  "cu.getbytes_pick": "`self.ptx` selects the getter PAIR; `cu.getbytes.c00`/`.c01` are the PTX arm",
  "cu.getbytes_pick0": "the CUBIN arm; `cu.getbytes_cubin`/`.cubin2` are its two calls",
  "cu.getbytes_zero": ("`create_string_buffer(0)` -- a consequence of the recorder answering 0 "
                       "for the size, not a ported decision"),
  "cu.nvrtcerr_kind": "`CompileError`; `cu.nvrtcerr_1` carries the message it carries",
  "cu.jiterr_kind": "`CompileError`; `cu.jiterr_1` carries the message it carries",
  "cu.jitlinkresult_0": "`nvJitLinkResult[0]`; `cu.jiterr_0` carries it inside the message",
  "cu.jitlinkresult_1": "`nvJitLinkResult[1]`; `cu.jiterr_1` carries it inside the message",
  "cu.jitlinkresult_6": "`nvJitLinkResult[6]`; `cu.jiterr_n` is the table's size and `cu.jiterr_15` is the absent one",
  "cpu.X86.args_n": "the refusal arm again; `cpu.sparc.args_n` is the same fact for another arch",
  "cpu.sparc.args": "the refusal arm builds NO list, so the joined string is empty; `cpu.sparc.kind` carries the refusal",
  "cpu.sparc.args_n": "the refusal arm's COUNT is 0; `cpu.sparc.kind` carries the refusal",
  "cpu.x86_64.target": "the `--target=` triple for x86_64; `cpu.arm64f.target` and `cpu.riscv64nf.target` are the others",
  "cpu.arm64f.target": "the arm64 triple; `cpu.x86_64.target` is the same def for x86_64",
  "cpu.riscv64nf.target": "the riscv64 triple; `cpu.x86_64.target` is the same def for x86_64",
  "cu.jiterr_0": "`jitlink_check(0)` does NOT raise, so there is no message to compare; the three real statuses are",
  "cu.nvrtc_v1204b.opts": "the no-`--minimal` option list; `cu.nvrtc_v1204.opts` is the `O2`-with-minimal arm",
  "cu.nvrtc_v1204b.opts_n": "see `cu.nvrtc_v1204b.opts`",
  "cu.nvptx_sm86.ptxlen": "the length nvJitLinkAddData is given, which is the parent's compiled PTX",
  "cu.jitlinkresult_15": (".get(15) is None -- an ABSENT name, which is a different answer from a "
                          "name and not the absence of a message"),
  "cu.disfn_prefix": "the `tinycuda_` prefix; `cu.disfn_ptx` is the prefix plus a digest",
  "cu.disfn_ptx_n": "the LENGTH of a name; `cu.disfn_ptx` is the name",
  "cu.disfn_zeros": "a digest fixture; `cu.disfn_ptx` is the second",
  "cu.disfn_empty": "a digest fixture; `cu.disfn_ptx` is the second",
  "cu.disfail": "the first half of the failure message; `cu.disfail2` is the second half",
  "cu.disptxas_cubin": ("`ptx=False` SKIPS the ptxas call entirely, so the empty string is the "
                        "answer; `cu.disptxas_ptx` is the true arm"),
  "cu.disptxas_empty": "see `cu.disptxas_cubin`",
  "cu.disnvdisasm_cubin": "`nvdisasm` runs in BOTH arms; `cu.disnvdisasm_ptx` is the other fixture",
  "cu.esc_black": ("the eight escape numbers are each compared by their own `cu.esc_*` row "
                   "against `cu.esc_black`..`cu.esc_white`; this one is the FIRST of the eight "
                   "and is compared by `cu.esc_red`.. too"),
  "cu.esc_red": "see `cu.esc_black`",
  "cu.esc_green": "see `cu.esc_black`",
  "cu.esc_yellow": "see `cu.esc_black`",
  "cu.esc_blue": "see `cu.esc_black`",
  "cu.esc_magenta": "see `cu.esc_black`",
  "cu.esc_cyan": "see `cu.esc_black`",
  "cu.esc_white": "see `cu.esc_black`",
  "cu.esc_open_34": "the escape OPENING, which `cu.colored_blue` carries inside its string",
  "cu.esc_reset": "the escape RESET, which `cu.colored_blue` carries inside its string",
  "cu.esc_bg_blue": "the background escape (the `10*background` term); `cu.colored_bgstr` is the string",
  "cu.colors_n": "the length of the eight colour names; the eight `cu.esc_*` rows are their values",
  "cu.colored_none": "`color=None` is the identity; `@4.cu.colored_nocolor_x` is the NO_COLOR arm",
  "cu.colored_red": "one of the eight escape STRINGS; `cu.esc_red` is its number",
  "cu.colored_green": "one of the eight escape STRINGS; `cu.esc_green` is its number",
  "cu.colored_yellow": "one of the eight escape STRINGS; `cu.esc_yellow` is its number",
  "cu.colored_magenta": "one of the eight escape STRINGS; `cu.esc_magenta` is its number",
  "cu.colored_cyan": "one of the eight escape STRINGS; `cu.esc_cyan` is its number",
  "cu.colored_black": "one of the eight escape STRINGS; `cu.esc_black` is its number",
  "cu.colored_white": "one of the eight escape STRINGS; `cu.esc_white` is its number",
  "cu.colored_bgstr": "the BACKGROUND string; `cu.esc_bg_blue` is its number",
  "cu.nvrtc_v1204.last": "the `--minimal` suffix; `cu.nvrtc_v1204.opts` carries the whole list",
  "cu.nvrtc_v1204.last0": "the no-`--minimal` suffix; `cu.nvrtc_v1204.opts` carries the whole list",
  "cu.nvrtc_v1204.calls": "the five call NAMES; `.calls_n`, `.first` and `.lastc` are the separate claims",
  "cu.nvrtc_v1204.lastc": "the destroy call; `cu.nvrtc_v1204.first` is the create call",
  "cu.nvrtc_v1204.nopts": "`len(self.compile_options)` is a property of `opts`, which is compared whole",
  "cu.nvrtc_v1204.name": "the `<null>` program name nvrtc is given; a Python string literal",
  "cu.nvrtc_v1204.arch": "the `--gpu-architecture=` prefix; `cu.nvrtc_v1204.opts` carries it",
  "cu.nvrtc_v1204.arch_ptx": "`cuda_disassemble(lib, arch, ptx=self.ptx)` -- WALL 2 (the artifact)",
  "cu.nvrtc_v1204.arch_cubin": "see `cu.nvrtc_v1204.arch_ptx`",
  "cu.nvcc_ptx.dis": "see `cu.nvrtc_v1204.arch_ptx`",
  "cu.nvcc_cubin.dis": "see `cu.nvrtc_v1204.arch_ptx`",
  "cu.ptxc_sm75.dis": "see `cu.nvrtc_v1204.arch_ptx`",
  "cu.nvptx_sm86.dis": "`cuda_disassemble(lib, arch)` with ptx defaulting to False; see WALL 2",
  "cu.nvcc_ptx.hex8": "the digest is a PARAMETER (WALL 3); `cu.nvcc_ptx.keystr` carries the key it is spliced into",
  "cu.nvcc_extra.hex8": "see `cu.nvcc_ptx.hex8`",
  "cu.nvcc_one.hex8": "see `cu.nvcc_ptx.hex8`",
  "cu.nvcc_ptx.join": "`' '.join([])` is the empty string; `cu.nvcc_extra.join` is the two-element arm",
  "cu.nvcc_one.join": "a one-element join; `cu.nvcc_extra.join` is the two-element arm",
  "cu.nvcc_cubin.cmd": "`cu.nvcc_ptx.cmd` is the same def with the other mode",
  "cu.nvcc_cubin.keystr": "the no-`ptx` cache-key arm; `cu.nvcc_ptx.keystr` is the other arm",
  "cu.nvcc_extra.keystr": "see `cu.nvcc_cubin.keystr` with another arch",
  "cu.nvcc_one.keystr": "see `cu.nvcc_cubin.keystr` with another arch",
  "cu.nvcc_suffixes": "the three suffixes TOGETHER; the `.mode`/`.suffix` rows are the individual pairs",
  "cu.nvcc_src_suffix": "the third suffix; `cu.nvcc_suffixes` carries all three",
  "cu.ptxc_empty.key": "the key does not read the version, so a short arch is fine here",
  "cu.ptxc_x.key": "see `cu.ptxc_empty.key`",
  "cu.ptxc_short.key": "see `cu.ptxc_empty.key`; `cu.ptxc_short.ver` is the version of a two-digit arch",
  "cu.ptxc_key_alt": "`cache_key='nv_ptx'`; `cu.nvptx_sm86.key` is the same key from the subclass",
  "cu.ptxc_empty.ver_ok": "the ValueError test; `cu.ptxc_sm75.ver` and `cu.ptxc_sm120.ver` are the answers",
  "cu.ptxc_compute86.ver_ok": "see `cu.ptxc_empty.ver_ok` -- `compute_86` makes `arch[3:]` a non-number",
  "cu.ptxc_sm75.out2": "a second fixture of `PTXCompiler.replace`; `cu.ptxc_sm86.out3` is the no-match arm",
  "cu.ptxc_sm75.out": "a second fixture of `PTXCompiler.compile`; `cu.ptxc_sm120.out` is the other version arm",
  "cu.ptxc_sm75.ver_ge120": "the 120 threshold's false arm; `cu.ptxc_sm120.ver_ge120` is the true one",
  "cu.ptxc_sm89.ver_ge89": "the 89 threshold's true arm; `cu.ptxc_sm88.ver_ge89` is the false one",
  "cu.ptxc_sm200.ver": "a two-hundred arch; `cu.ptxc_sm120.ver` is the 120 boundary",
  "cu.ptxc_sm90.ver": "a boundary between 89 and 120; `cu.ptxc_sm89.ver` is the 89 boundary",
  "cu.ptxc_sm88.ver": "the 89 boundary from below; `cu.ptxc_sm89.ver` is the boundary itself",
  "cu.ptxc_sm86.ver": "a mid fixture; `cu.ptxc_sm75.ver` and `cu.ptxc_sm88.ver` bracket it",
  "cu.nvptx_sm120.key": "`cu.nvptx_sm86.key` is the same def with another arch",
  "cu.nvptx_sm120.calls": "the call SEQUENCE does not depend on the arch; `cu.nvptx_sm86.calls` is it",
  "cu.nvptx_sm120.input": "`cu.nvptx_sm86.input` is the same library constant",
  "cu.nvptx_sm120.archopt": "`cu.nvptx_sm86.archopt` is the same def with another arch",
  "cu.nvptx_sm86.first": "the first of six calls; `cu.nvptx_sm86.calls` carries the order",
  "cu.nvptx_sm86.lastc": "the last of six calls; `cu.nvptx_sm86.calls` carries the order",
  "cu.nvptx_sm86.calls_n": "the COUNT of the sequence; `cu.nvptx_sm86.calls` carries its content",
  "cu.nvptx_sm86.archopt_n": ("the arity of the `-arch=` option list; `cu.nvptx_sm86.archopt` is the "
                              "content, and reading a `to_char_p_p` array out of the recorder SEGFAULTS, "
                              "so that one row is declared rather than measured"),
  "cu.nvptx_sm86.archopt": ("`-arch={arch}` -- an f-string over the arch. The oracle CANNOT read the "
                            "`to_char_p_p` array the recorder was handed without segfaulting "
                            "(MEASURED: `ext_oracle.py` exits 139 on `_cstr` of that argument), so "
                            "the row is declared and the SIX-CALL SEQUENCE is compared instead"),
  "cu.nvptx_sm120.archopt": "see `cu.nvptx_sm86.archopt`",
  "cu.nvptx_sm86.ptxlen": "the length of the parent's compiled PTX; `cu.nvptx_sm86.input` is the kind",
  "cu.nvptx_sm86.inputname": "the `<null>` name; see `cu.nvptx_sm86.input_name`",
  "cu.nvptx_sm86.input_name": "the `<null>` name nvJitLinkAddData is given; a Python string literal",
  "cu.cudapath_set_n": "`cu.inc_set_n` is the same count from the same def",
  "cu.cudapath_set_opts": "`cu.nvrtc_v1204.opts` is the same option list with the path UNSET",
  # --- compiler_llvm.bend ----------------------------------------------
  "ll.cerr_inner": "`ctypes.c_char` -- the innermost type of `cerr()`; `ll.cerr_depth` is the load-bearing part",
  "ll.expect_f0_0": "`if x:` with a falsy `x`; `ll.expect_f0_1` is the truthy arm",
  "ll.expect_ret_str": "the `ret` argument returned UNCHANGED; `ll.expect_ret_none` is the default",
  "ll.expect_msg": "the `isinstance(err, str)` arm; `ll.expect_msg2` is a second message",
  "ll.arch_arm64.passes": ("`default<O2>` for `LLVMOPT` set; `@3.ll.passes_opt0` is the `O0` arm, "
                           "and it is the ONLY place `O0` can be observed"),
  "ll.arch_arm64.passes0": "see `ll.arch_arm64.passes`",
  "ll.arch_arm64.pbo_flag": "the `True` argument of the four `Set*` calls; `ll.arch_arm64.pbosets` names them",
  "ll.arch_arm64.pbosets_n": ("4 against 0 is the branch, and the zero arm is `ll.pbosets_n0` in "
                              "the `@3` process"),
  "ll.arch_arm64.tm_processor": "the `processor` argument; `ll.arch_arm64.tm_feats` is the other one",
  "ll.arch_arm64.tm_feats": "the `feats` argument; `ll.arch_arm64.tm_processor` is the other one",
  "ll.tm_args_n": "the arity of `LLVMCreateTargetMachine`; its two interesting arguments are compared",
  "ll.arch_AMDGPU.prefix": "the `.get` DEFAULT; `ll.arch_arm32.prefix` reaches it a different way",
  "ll.arch_EMPTY.prefix": "the `.get` default for the empty string",
  "ll.arch_EMPTY.triple": "`KeyError: ''`; `ll.arch_arm32.triple` is the same refusal with a name",
  "ll.arch_AMDGPU.triple_ok": "the LITERAL `AMDGPU` key, which is not an arch name but the map's key",
  "ll.triple_n": "the SIZE of the triple map; the three `ll.arch_*_*.triple` rows are its entries",
  "ll.arch_AMDGPU.triple": "the `AMDGPU` entry; the arm64 and x86_64 rows are the other two",
  "ll.ckey_mykey": "the `or` taking the GIVEN key; `ll.ckey_NONE` and `ll.ckey_` are the f-string arm",
  "ll.ckey_": "an EMPTY cache key falls into the f-string arm, because `or` treats '' as false",
  "ll.diags_n0": "a fresh instance's list is EMPTY; `ll.append_ok_n` is the collect",
  "ll.append_ok": "the `LLVMDSError` arm; `ll.append_no` is the arm that collects nothing",
  "ll.append_no_n": "the COUNT for the non-error severity; `ll.append_no` is the same def",
  "ll.append_ok2": "a second collected message; `ll.diags_join` is the join of two",
  "ll.comp.c00": "the FIRST of the nine call names; `ll.comp_n` is the COUNT and the ORDER is WALL 1",
  "ll.comp_n": "the COUNT of `compile`'s calls; the ORDER and IDENTITY are WALL 1 (the `llvm` CDLL)",
  "ll.comp_expects": "there are three `expect()` calls in `compile`; their bodies are WALL 1",
  "ll.comp_cleared": "`self.diag_msgs.clear()`; `ll.diags_n0` is the state it leaves",
  "ll.runpasses_err": "the `isinstance(err, str)` message at `LLVMRunPasses`; `ll.expect_msg2` is the same arm",
  "ll.comp_diag_msg": "the oracle's raised message for ONE diagnostic; `ll.comp_diag2_msg` is two",
  "ll.comp_diag2_msg": "the oracle's raised message for TWO, so the join is a join and not a single message",
  "ll.del_n_pbo": "one of the two `hasattr` guards false; `ll.del_n` is both true",
  "ll.del_order_pbo": "the pbo-only dispose ORDER; `ll.del_order` is both",
  "ll.del_n_ctx": "the other guard false; `ll.del_n` is both",
  "ll.del_order_ctx": "the context-only dispose ORDER; `ll.del_order` is both",
  "ll.del_n_none": "neither guard -- a constructor that raised leaves nothing to dispose",
  "ll.del_order_none": "see `ll.del_n_none`",
  "ll.cpu_x86.featstr": "an EMPTY feats list; `ll.cpu_x86f.featstr` is the non-empty arm",
  "ll.cpu_x86.feat_final": "the empty-features final string; `ll.cpu_x86f.feat_final` is the other",
  "ll.cpu_x86n.featstr": "`featstr` BEFORE the host features are appended; `ll.cpu_x86n.feat_final` is after",
  "ll.cpu_x86.cpu": "a NON-native cpu passes through; `ll.cpu_x86n.cpu` is the native arm",
  "ll.cpu_arm.featstr": "the arm64 features BEFORE the x18 prefix; `ll.cpu_arm.feat_final` is after",
  "ll.cpu_arm.x18": "the prefix on its own; `ll.cpu_arm.feat_final` is the concatenation",
  "ll.cpu_x18_x86": "the empty arm; `ll.cpu_x18_arm` is the `+reserve-x18,` arm",
  "ll.cpu_rv.triple_ok": "`riscv64` reaching the KeyError; `ll.arch_riscv64.triple_ok` is the same test",
  "ll.cpu_ge2_one": "the assert's false arm; `ll.cpu_ge2_two` is the true arm",
  "ll.cpu_host_cpu": "`LLVMGetHostCPUName()` -- the recorder's value, so a DECLARED constant",
  "ll.cpu_host_feats": "`LLVMGetHostCPUFeatures()` -- the recorder's value, so a DECLARED constant",
  "ll.cpu_dis": "`cpu_objdump(lib)` -- WALL 3; the library is bytes",
  "ll.amd_arch": "the `arch` passed to `super().__init__`; `ll.amd_feats` is the third argument",
  "ll.amd_feats": "`+cumode`; `ll.amd_triple_ok` is the arch it is legal for",
  "ll.amd_triple_ok": "the `AMDGPU` key; `ll.arch_AMDGPU.triple_ok` is the same test",
  "ll.amd_reduce_kind": "the CLASS in `__reduce__`; `ll.amd_reduce_arg` is the payload",
  "ll.amd_reduce_n": "the arity of the reduce tuple; `ll.amd_reduce` is the whole thing",
  "ll.amd_reduce_arg": "the one-tuple's element; `ll.amd_reduce` is the whole thing",
  "ll.amd_reduce": "the whole `__reduce__`; the class and the arity are its two parts",
  "ll.amd_hint": "the appended hint; `ll.remap_amdgcn_msg` is the concatenation",
  "ll.amd_needle": "the substring; `ll.remap_amdgcn` is the predicate over it",
  "ll.remap_other": "a RuntimeError that does NOT match; `ll.remap_amdgcn` is the match",
  "ll.remap_plain": "`undefined value` WITHOUT the `@llvm.amdgcn.` prefix does not match",
  "ll.remap_amdgcn_end": "the needle at the END still matches -- `in`, not `startswith`",
  "ll.remap_other_msg": "the UNCHANGED message; `ll.remap_amdgcn_msg` is the appended one",
  "ll.remap_plain_msg": "see `ll.remap_other_msg`",
  "ll.remap_amdgcn_end_msg": "see `ll.remap_amdgcn_msg` with the needle at the end",
  "ll.remap_amdgcn_kind": "which arm answered; `ll.remap_amdgcn_msg` is the value",
  "ll.remap_other_kind": "see `ll.remap_amdgcn_kind`",
  "ll.amd_dis": "`amdgpu_disassemble(lib)` -- WALL 3",
  "ll.const_LLVMDSError": "a library constant, DECLARED; `ll.append_ok` is the arm it drives",
  "ll.const_LLVMReturnStatusAction": "a library constant, DECLARED; WALL 1",
  "ll.const_LLVMObjectFile": "a library constant, DECLARED; WALL 1",
  "ll.const_LLVMCodeGenLevelDefault": "a library constant, DECLARED; WALL 1",
  "ll.const_LLVMRelocPIC": "a library constant, DECLARED; WALL 1",
  "ll.const_LLVMCodeModelDefault": "a library constant, DECLARED; WALL 1",
  "ll.ckey_mykey_opt0": "a second fixture of the `O0` key; `ll.ckey_NONE_opt0` is the compared one",
  "ll.key_opt0": "a restatement of `ll.ckey_NONE` with the flag TRUE; `ll.ckey_NONE_opt0` is FALSE",
}

# bend row count per file, checked as an ABSOLUTE number
EXPECT = {"amd": 94, "compiler_cpu": 107, "compiler_cuda": 163, "compiler_llvm": 119}


def run(cmd, **kw):
  return subprocess.run(cmd, capture_output=True, text=True, timeout=900, cwd=str(ROOT), **kw)


def rows_of(path):
  d = {}
  for line in pathlib.Path(path).read_text(errors="replace").splitlines():
    if "=" not in line: continue
    k, _, v = line.partition("=")
    d.setdefault(k, v)
  return d


def is_marker(k):
  base = k[:-2] if k.endswith("=1") else k
  return base.endswith("_done") or base.endswith("-done")


def identity(k):
  return "am." + k[4:] if k.startswith("amd.") else k


def main():
  fails = []

  # ---- 1. the oracle, FIVE PROCESSES, one per configuration ------------
  ORACLE = {}
  for tag, env, secs in RUNS:
    out = SLOP / f"ext_oracle_{tag}.txt"
    r = run([str(PY), "-u", str(ORACLE_PY)] + secs, env=dict(os.environ, **env))
    out.write_text(r.stdout)
    if r.returncode != 0:
      fails.append(f"ORACLE@{tag} exit {r.returncode}: {(r.stdout + r.stderr)[:400]}")
    meta = {}
    for line in r.stdout.splitlines():
      if line.startswith("META."):
        _, name, val = line.split(".")
        meta[name] = int(val.split("=")[1])
    for nm in secs:
      if meta.get(nm, 0) == 0:
        fails.append(f"ORACLE@{tag} SECTION {nm} EMITTED ZERO ROWS")
    for k, v in rows_of(out).items():
      if k.startswith("META."): continue
      ORACLE["@" + tag + "." + k] = v
      if tag == "0": ORACLE.setdefault(k, v)

  # ---- 2 and 3. the bend lanes ----------------------------------------
  BEND_ROWS, counts = {}, {}
  for f in UNITS:
    src = ROOT / f"tinybendygrad/runtime/support/{f}.bend"
    if not src.exists():
      fails.append(f"MISSING {src}"); continue
    chk = run([str(BEND), str(src), "--check-only"])
    v = (chk.stdout + chk.stderr).strip().splitlines()
    verdict = v[0] if v else "(no output)"
    # `--check-only` exits 1 even on a clean file because dtype.bend has 14
    # unfilled laws, so the FIRST LINE is the signal and not the exit status.
    if "SOME PROOFS FAIL" in verdict:
      fails.append(f"{f}: {verdict}")
    # bend 2.0.34's machine stack overflows on ~1 run in 20 and prints ZERO
    # rows when it does, and a 0-row result is indistinguishable from "not
    # started", so a 0-row run is RE-RUN rather than believed.
    it = None
    for _ in range(4):
      cand = run([str(BEND), str(src)])
      if cand.returncode == 0 and "=" in cand.stdout:
        it = cand; break
    if it is None:
      fails.append(f"{f} interpreted: four runs, none printed a row "
                   f"(stack overflow, or a real failure)")
      continue
    nat = SLOP / f"ext-{f}-native"
    cp = run([str(BEND), str(src), "-o", str(nat)])
    if cp.returncode != 0:
      fails.append(f"{f} compile exit {cp.returncode}"); continue
    nv = None
    for _ in range(4):
      cand = run([str(nat)])
      if cand.stdout: nv = cand; break
    if nv is None:
      fails.append(f"{f} native: four runs, none printed a row"); continue
    if it.stdout != nv.stdout:
      fails.append(f"{f}: LANES DIFFER")
      for a, b in zip(it.stdout.splitlines(), nv.stdout.splitlines()):
        if a != b: fails.append(f"   interp {a!r} != native {b!r}")
    (SLOP / f"ext-{f}-interp.txt").write_text(it.stdout)
    n = len([l for l in it.stdout.splitlines() if "=" in l and not is_marker(l.partition("=")[0])])
    counts[f] = n
    if n != EXPECT[f]:
      fails.append(f"{f}: {n} rows, expected {EXPECT[f]}")
    BEND_ROWS[f] = rows_of(SLOP / f"ext-{f}-interp.txt")

  ALL = {}
  for d in BEND_ROWS.values(): ALL.update(d)

  # ---- 4. every row accounted for ------------------------------------
  mapping = dict(EXCEPTIONS)
  for k, (tag, on) in FRESH.items(): mapping[k] = "@" + tag + "." + on
  for k in sorted(ALL):
    if is_marker(k): continue
    if k in UNCHECKED or k in mapping: continue
    if identity(k) in ORACLE: continue
    fails.append(f"UNMAPPED BEND ROW (no oracle row): {k}={ALL[k]!r}")
  for k in mapping:
    if k not in ALL and k not in UNCHECKED:
      fails.append(f"MAPPED BEND ROW MISSING: {k}")

  # ---- 5. compare whole `name=value` LINES ---------------------------
  checked = 0
  for k in sorted(ALL):
    if is_marker(k) or k in UNCHECKED: continue
    on = mapping.get(k, identity(k))
    if on not in ORACLE:
      fails.append(f"ORACLE ROW MISSING for {k} -> {on}"); continue
    checked += 1
    if ALL[k] != ORACLE[on]:
      fails.append(f"MISMATCH {k}\n   bend   ={ALL[k]!r}\n   oracle={ORACLE[on]!r}   ({on})")

  secs = {}
  for k, v in ORACLE.items():
    if k.startswith("@0.META."): secs[k[6:]] = v
  print(f"oracle rows      : {len(ORACLE)} over {len(RUNS)} PROCESSES")
  print(f"oracle sections  : {sorted(secs)}")
  print(f"bend rows        : {len(ALL)} across {len(BEND_ROWS)} files  {counts}")
  print(f"rows compared    : {checked}")
  print(f"rows UNCHECKED   : {len(UNCHECKED)} (each with a reason in ext_check.py)")
  if fails:
    print(f"\n=== {len(fails)} PROBLEM(S) ===")
    for f in fails[:80]: print("  " + f)
    if len(fails) > 80: print(f"  ... and {len(fails) - 80} more")
    sys.exit(1)
  print("\nALL CHECKS PASS")


if __name__ == "__main__":
  main()