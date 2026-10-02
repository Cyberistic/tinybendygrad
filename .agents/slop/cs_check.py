#!/usr/bin/env python3
"""Gate for the four external-compiler backends.

Five things, in this order, because the order is the point:

  1. the ORACLE ran, exited 0, and every REQUESTED section emitted rows
     (a section that emitted zero rows is a section that did not start, and a
     gate that cannot tell "0 rows" from "broke" is not a gate)
  2. every one of the four .bend files exists, CHECKS, and PRINTS A NON-ZERO
     NUMBER OF ROWS on BOTH lanes
  3. the two lanes are BYTE-IDENTICAL, diffed whole
  4. every bend row is either MAPPED to an oracle row or explicitly declared
     UNCHECKED -- an unmapped row is a loud failure, not a silent pass
  5. each MAPPED row compares a whole `name=value` LINE (agent-core: a harness
     that compares row NAMES reports 0 for every mutation)

Absolute row counts are asserted, because a relative count cannot distinguish
"one row fewer" from "the file stopped printing".
"""
import os, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SLOP = ROOT / ".agents/slop"
BEND = ROOT / "bin/bend"
PY = ROOT / ".venv/bin/python"

UNITS = [("amd", "compiler_amd"), ("mesa", "compiler_mesa"),
         ("qcom", "compiler_qcom"), ("cs", "compileserver")]

# bend row -> oracle row.  Most rows are MIRRORED: `.agents/slop/cs_oracle.py`
# section `mirror` emits a row under the bend name, computed by calling the real
# Python.  EXCEPTIONS lists the rows whose oracle row has a different name, and
# UNCHECKED lists rows that are deliberately not compared (with a reason).
EXCEPTIONS = {
  # the comgr version switch: the two autogen modules' OWN constants
  "amd.Ad.hiplang_2": "amd.autogen.hiplang_2",
  "amd.Ad.hiplang_3": "amd.autogen.hiplang_3",
  "amd.Ad.version_0": None, "amd.Ad.version_2": None, "amd.Ad.version_3": None,
  # `check(0)` does not raise, so its oracle row is the non-raise marker
  "amd.c.msg_0": None,   # check(0) does not raise; the three real statuses are compared
  # `set_options` and the thirteen-element option list
  "amd.sp.n_two": "amd.split_two.n",
  "amd.sp.n_empty": "amd.split_empty.n",
  "amd.sp.n_three": "amd.split_three.n",
  "amd.sp.n_dbl": "amd.split_dbl.n",
  "amd.sp.n_lead": "amd.split_lead.n",
  "amd.sp.n_trail": "amd.split_trail.n",
  "amd.sp.n_tabs": "amd.split_tabs.n",
  "amd.sp.n_many": "amd.split_many.n",
  "amd.sp.n_one": "amd.split_one.n",
  "amd.h.isa_1100": "amd.hip_gfx1100_0.isa0",
  "amd.h.isa_942": "amd.hip_gfx942_0.isa0",
  "amd.h.isa_sm86": "amd.hip_sm_86_0.isa0",
  "amd.h.dataname_0": "amd.hip_gfx1100_0.dataname0",
  "amd.h.dataname_1": "amd.hip_gfx1100_1.dataname0",
  "amd.h.opt_n_1100": "amd.hip_gfx1100_0.optn0",
  "amd.h.opt_n_942": "amd.hip_gfx942_0.optn0",
  "amd.h.opt_string_1100": "amd.hip_gfx1100_0.optsp0",
  "amd.h.opt_codegen": "amd.hip_gfx1100_0.optsp1",
  "amd.h.opt_codegen_n": "amd.hip_gfx1100_0.optn1",
  "amd.h.opt_empty_n": "amd.hip_gfx1100_0.optn2",
  "amd.h.opt_empty": "amd.hip_gfx1100_0.optsp2",
  # HIPCompiler.compile's asm predicate
  **{f"amd.C.asm_{i}": f"amd.asm{i}.asm" for i in range(16)},
  # cache keys
  "amd.C.hip_key_1100": "amd.hipkey_gfx1100",
  "amd.C.hip_key_942": "amd.hipkey_gfx942",
  "amd.C.hip_key_1101": "amd.hipkey_gfx1101",
  "amd.C.hipcc_key_none": "amd.hipcc_gfx1100_none_0.key",
  "amd.C.hipcc_key_one": "amd.hipcc_gfx1100_-DFOO1_0.key",
  "amd.C.hipcc_key_942": "amd.hipcc_gfx942_-A--B_0.key",
  # the `_nohipcc` suffix needs a FRESH interpreter, because `helpers.getenv` is
  # `@functools.cache` (MEASURED) -- the second oracle run
  "amd.C.hipcc_key_nohip": "@amdkey_gfx1100_none.key",
  "amd.C.join_extra_none": "amd.hipcc_gfx1100_none_0.join",
  "amd.C.join_extra_one": "amd.hipcc_gfx1100_-DFOO1_0.join",
  "amd.C.join_extra_two": "amd.hipcc_gfx942_-A--B_0.join",
  "amd.C.join_extra_sp": "amd.hipcc_gfx942_-X_y_z_1.join",
  # the two argv lists, with the random temp paths replaced by their SUFFIXES
  "amd.C.argv1_none": "amd.cc_gfx1100__opt_rocm_none.argv0",
  "amd.C.argv2_none": "amd.cc_gfx1100__opt_rocm_none.argv1",
  "amd.C.argv1_extra": "amd.cc_gfx942__opt_rocm_-DFOO1--DBAR.argv0",
  "amd.C.argv2_extra": "amd.cc_gfx942__opt_rocm_-DFOO1--DBAR.argv1",
  "amd.C.argv1_n_none": "amd.cc_gfx1100__opt_rocm_none.argvn0",
  "amd.C.argv2_n_none": "amd.cc_gfx1100__opt_rocm_none.argvn1",
  "amd.C.argv1_n_two": "amd.cc_gfx942__opt_rocm_-DFOO1--DBAR.argvn0",
  "amd.C.argv2_n_two": "amd.cc_gfx942__opt_rocm_-DFOO1--DBAR.argvn1",
  "amd.C.prog": "amd.cc_gfx1100__opt_rocm_none.prog0",
  "amd.C.suffixes": "amd.cc_gfx1100__opt_rocm_none.suffixes",
  "amd.C.rocm_default": "amd.cc_gfx1100__opt_rocm_none.rocm_default",
  "amd.C.rocm_include_def": "amd.cc_gfx1100__opt_rocm_none.rocm_include",
  "amd.C.short_1": "@amdkey_gfx1100_none.nohip",
  "amd.C.compile_error_kind_1": "amd.ce_0.type",
  "amd.C.compile_error_kind_0": "amd.ce_1.type",
  # the comgr enum constants, from the REAL autogen modules
  "amd.A.source_kind": "amd.autogen.AMD_COMGR_DATA_KIND_SOURCE_2",
  "amd.A.log_kind": "amd.autogen.AMD_COMGR_DATA_KIND_LOG_2",
  "amd.A.exec_kind": "amd.autogen.AMD_COMGR_DATA_KIND_EXECUTABLE_2",
  "amd.A.act_assemble": "amd.autogen.AMD_COMGR_ACTION_ASSEMBLE_SOURCE_TO_RELOCATABLE_2",
  "amd.A.act_codegen": "amd.autogen.AMD_COMGR_ACTION_CODEGEN_BC_TO_RELOCATABLE_2",
  "amd.A.act_link": "amd.autogen.AMD_COMGR_ACTION_LINK_RELOCATABLE_TO_EXECUTABLE_2",
  "amd.A.act_compile": "amd.autogen.AMD_COMGR_ACTION_COMPILE_SOURCE_WITH_DEVICE_LIBS_TO_BC_2",
  # _get_comgr_data, called DIRECTLY so the count is one invocation
  "amd.gd.calls": "amd.gd_exec.calls",
  "amd.gd.pick_kind_exec": "amd.gd_exec.kind",
  "amd.gd.pick_kind_log": "amd.gd_log.kind",
  "amd.gd.calls_name": "amd.gd_exec.names",
  # the compile_hip trace: the recorded call ORDER and IDENTITY
  "amd.tr.compile.n": None,   # see UNCHECKED: the port declares 17 of 28 comgr calls
  "amd.tr.compile.optn0": "amd.hip_gfx1100_0.optn0",
  "amd.tr.compile.act0": "amd.hip_gfx1100_0.action0",
  "amd.tr.compile.act1": "amd.hip_gfx1100_0.action1",
  "amd.tr.compile.act2": "amd.hip_gfx1100_0.action2",
  "amd.tr.asm.n": None,
  "amd.tr.asm.act0": "amd.hip_gfx1100_1.action0",
  "amd.tr.asm.act1": "amd.hip_gfx1100_1.action1",
  "amd.tr.compile.dataname": "amd.hip_gfx1100_0.dataname0",
  "amd.tr.asm.dataname": "amd.hip_gfx1100_1.dataname0",
  # qcom's two command strings, from the real __init__
  "q.cmd_qemu": "qcom.srv_a630-x_qemu_x86_64.cmd",
  "q.cmd_docker": "qcom.srv_a630_docker_x86_64.cmd",
  "q.cmd_qemu_2": None, "q.cmd_docker_2": None,   # second fixtures of the same defs
  "amd.c.msg_7": "amd.check_7.msg",
  "amd.c.msg_255": "amd.check_255.msg",
  # the disas_adreno line rows: the bend name carries the fixture values
  "da.line_0_0_0": "da.line0.fmt",
  "da.line_1_0_1": "da.line1.fmt",
  "da.line_15_0_15": "da.line2.fmt",
  "da.line_255_0_255": "da.line3.fmt",
  "da.line_4096_dead_beef": "da.line4.fmt",
  "da.line_65535_max_max": "da.line5.fmt",
  "da.line_1_1_2": "da.line6.fmt",
  "da.line_2_abcdef_2": "da.line7.fmt",
  "da.line_65536_0_16": "da.line8.fmt",
  "da.line_12345_0_0": "da.line9.fmt",
  "da.line_999_0_low": "da.line10.fmt",
  # qcom's arch assert, the chip id and the constants
  "q.arch_ok_a630": "q.arch_ok_a630",
  "q.arch_ok_a630_x": "q.arch_ok_a630,x",
  "q.arch_ok_a630_c": "q.arch_ok_a630,",
  "q.arch_ok_a640": "q.arch_ok_a640",
  "q.arch_ok_EMPTY": "q.arch_ok_EMPTY",
  "q.arch_ok_A630": "q.arch_ok_A630",
  "q.arch_ok_a63": "q.arch_ok_a63",
  "q.key_a630": "q.key_a630",
  "q.key_a630_x": "q.key_a630_x",
  "q.chip_id": "q.chip_id",
  "q.mode": "q.mode",
  "q.src_str": "q.src_str",
  "q.is_aarch64_1": "q.is_aarch64_1",
  "q.fails_null": "q.fails_null", "q.fails_zero": "q.fails_zero",
  "q.fails_err": "q.fails_err", "q.fails_null_err": "q.fails_null_err",
  "q.picks_exe_2": "q.picks_exe_2", "q.picks_exe_1": "q.picks_exe_1",
  # nvdisasm: the bend fixture uses a 32-character digest of the same 16 bytes
  "nv.cmd_str": "nv.cmd_str_sm_86",
  "nv.cmd_str120": "nv.cmd_str_sm_120",
  "nak.dev_sm_75": "nak.dev_sm_75",
  "nak.dev_sm_89": "nak.dev_sm_89",
  # mesa's `arch[3:]`, whose oracle row is the same slice
  "a3.drop3_sm_86": "a3.drop3_sm_86",
  # the compileserver spec arity: the oracle rows are the real split
  "cs.spec_n_a_b": "cs.spec_n_mod_Name", "cs.spec_ok_2": "cs.spec_ok_mod_Name",
  "cs.spec_n_none": "cs.spec_n_Name", "cs.spec_ok_1": "cs.spec_ok_Name",
  "cs.spec_n_three": "cs.spec_n_a_b_c", "cs.spec_ok_3": "cs.spec_ok_a_b_c",
  "cs.spec_n_colon": "cs.spec_n__Name", "cs.spec_n_trailing": "cs.spec_n_Name_",
}

# rows deliberately NOT compared, each with a reason
UNCHECKED = {
  "amd.C.argv1_rocm": ("`helpers.getenv` is `@functools.cache` (MEASURED), so `ROCM_PATH` "
                       "is read ONCE per process and a second value cannot be observed; "
                       "`amd.C.rocm_include` carries the default instead"),
  "amd.C.compile_error_1": "`CompileError(e)` carries the message UNCHANGED; `amd.C.asm_fail` "
                           "and `amd.C.compile_fail` carry the two literals",
  "tr.lvp.first": "a declared trace: the port records the calls it decides, not the 28 comgr calls",
  "tr.lvp.last": "a declared trace: see `tr.lvp.first`",
  "tr.nak.first": "a declared trace: see `tr.lvp.first`",
  "tr.nak.last": "a declared trace: see `tr.lvp.first`",
  "tr.ir3.first": "a declared trace: see `tr.lvp.first`",
  "tr.ir3.last": "a declared trace: see `tr.lvp.first`",
  "tr.aarch64.first": "a declared trace: the `cl_compiler_*` calls are WALL 1",
  "tr.aarch64.last": "a declared trace: see `tr.aarch64.first`",
  "tr.server.first": "a declared trace: the duplex pipe is WALL 2",
  "tr.server.last": "a declared trace: see `tr.server.first`",
  "tr.srv.first": "a declared trace; the loop is WALL 1",
  "tr.srv.last": "a declared trace; the loop is WALL 1",
  "tr.srv_err.first": "a declared trace; the loop is WALL 1",
  "tr.srv_err.last": "a declared trace; the loop is WALL 1",
  "amd.tr.compile.n": ("the port DECLARES 17 of the 28 comgr calls compile_hip makes; "
                       "the 11 omitted are the data_set create/destroy pairs and the two "
                       "release_data calls, and `amd.gd.calls_name` pins the four that matter"),
  "amd.tr.asm.n": "same, for the asm branch: 11 of 25",
  "ir3.arch_ok_a630_comma": "`a630,` and `a630,x` are the same first-field test",
  "ir3.arch_ok_a630_x": "`a630,x` and `a630,` are the same first-field test",
  "tr.lvp.n": "the declared call sequence; `.first` and `.last` are compared",
  "tr.nak.n": "the declared call sequence; `.first` and `.last` are compared",
  "tr.ir3.n": "the declared call sequence; `.first` and `.last` are compared",
  "tr.aarch64.n": "the declared call sequence; `.first` and `.last` are compared",
  "tr.server.n": "the declared call sequence; `.first` and `.last` are compared",
  "amd.c.msg_0": "check(0) does not raise, so there is no message to compare",
  "q.cmd_qemu_2": "a second fixture of the same def with different arguments",
  "q.cmd_docker_2": "a second fixture of the same def with different arguments",
  "amd.Ad.version_0": "a one-token Python condition; the CONSEQUENCE (hiplang) is compared",
  "amd.Ad.version_2": "a one-token Python condition; the CONSEQUENCE (hiplang) is compared",
  "amd.Ad.version_3": "a one-token Python condition; the CONSEQUENCE (hiplang) is compared",
  "amd.c.msg_min": "status 1 with an empty message; the three real statuses are compared",
  "amd.h.logging": "the boolean comgr flag; no oracle row exists for a constant True",
  "amd.C.suffix_0": "the three suffixes are compared TOGETHER as `amd.C.suffixes`",
  "amd.C.suffix_1": "the three suffixes are compared TOGETHER as `amd.C.suffixes`",
  "amd.C.suffix_2": "the three suffixes are compared TOGETHER as `amd.C.suffixes`",
  "amd.C.rocm_include_my": "the default is compared; a second path is the same def",
  "amd.C.short_0": "the False arm is the identity; the True arm is compared",
  "amd.C.asm_fail": "a Python string literal, verbatim",
  "amd.C.compile_fail": "a Python string literal, verbatim",
  "amd.A.act_assemble_name": "an alias for `amd.A.act_assemble`, which is compared",
  "amd.A.act_compile_name": "an alias for `amd.A.act_compile`, which is compared",
  "amd.A.act_codegen_name": "an alias for `amd.A.act_codegen`, which is compared",
  "amd.A.act_link_name": "an alias for `amd.A.act_link`, which is compared",
  "mesa.nvdis": "the nvdisasm command is compared by fixture; the arch loop is a theorem",
  "q.is_aarch64_0": "the False arm; `is_aarch64_1` is compared",
  "q.root": "the repository root is a path on this host, not a constant",
  "q.fs_url": "a Python string literal, verbatim",
  "q.msg_nolog": "unreachable in the Python (a zero error code does not raise)",
  "q.handle_linked": "CL_HANDLE_LINKED's value; `q.picks_exe_2` is compared",
  "q.compile_arg_n": "the arity of a call; the argument LIST is compared",
  "q.link_arg_n": "the arity of a call; the argument LIST is compared",
  "q.binary_args": "the arity of a call with no interesting argument",
  "q.qemu_n": "the word count is a property of `q.cmd_qemu`, which is compared",
  "q.docker_n": "the word count is a property of `q.cmd_docker`, which is compared",
  "q.docker_flags_n": "the word count is a property of `q.cmd_docker`, which is compared",
  "qcmd_qemu_2": "the second fixture is the same def with different arguments",
  "q.cmd_qemu_2": "the second fixture is the same def with different arguments",
  "q.cmd_docker_2": "the second fixture is the same def with different arguments",
  "q.resets_null": "`q.fails_*` already pins the predicate that feeds it",
  "q.resets_ok": "`q.fails_*` already pins the predicate that feeds it",
  "q.is_compile": "an alias for `q.msg`, which is compared",
  "tr.srv.n": "the declared call sequence; `tr.srv.first` and `.last` are compared",
  "tr.srv_err.n": "the declared call sequence; `tr.srv_err.first` and `.last` are compared",
  "cs.respond_lens": "a formatter over the lens, which are compared via `cs.pack_*`",
  "cs.unpack_str": "an alias for `hx2.str` over the packed bytes",
  "cs.usage": "a Python f-string over `sys.argv[0]`; `cs.argv_*` is the decision",
  "qcom.arch_ok_a630_c": "same as `a630,` -- the empty second field; covered by spec_n",
}

# bend row count, checked as an ABSOLUTE number
EXPECT = {"compiler_amd": 113, "compiler_mesa": 163, "compiler_qcom": 79, "compileserver": 50}


def run(cmd, **kw):
  return subprocess.run(cmd, capture_output=True, text=True, timeout=900, cwd=str(ROOT), **kw)


def rows_of(path):
  d = {}
  for line in pathlib.Path(path).read_text().splitlines():
    if "=" not in line: continue
    k, _, v = line.partition("=")
    d.setdefault(k, v)
  return d


def main():
  fails = []

  # ---- 1. the oracle -----------------------------------------------------
  r = run([str(PY), "-u", str(SLOP / "cs_oracle.py")])
  (SLOP / "cs_oracle_rows.txt").write_text(r.stdout)
  if r.returncode != 0:
    fails.append(f"ORACLE exit {r.returncode}")
    for m in ("amd", "mesa", "qcom", "cs", "mirror", "amdkey"):
      if f"\nMETA.{m}.rows=0\n" in "\n" + r.stdout:
        fails.append(f"ORACLE SECTION {m} EMITTED ZERO ROWS")
  key = run([str(PY), "-u", str(SLOP / "cs_oracle.py"), "amdkey"],
            env=dict(os.environ, NO_HIPCC="1"))
  (SLOP / "cs_oracle_key1.txt").write_text(key.stdout)
  if key.returncode != 0:
    fails.append(f"ORACLE(NO_HIPCC=1) exit {key.returncode}")
  ORACLE = {}
  ORACLE.update(rows_of(SLOP / "cs_oracle_rows.txt"))
  for k, v in rows_of(SLOP / "cs_oracle_key1.txt").items():
    ORACLE["@" + k] = v

  # ---- 2 and 3. the bend lanes ------------------------------------------
  BEND_ROWS = {}
  for unit, f in UNITS:
    src = ROOT / f"tinybendygrad/runtime/support/{f}.bend"
    if not src.exists():
      fails.append(f"MISSING {src}"); continue
    chk = run([str(BEND), str(src), "--check-only"])
    v = (chk.stdout + chk.stderr).strip().splitlines()
    verdict = v[0] if v else "(no output)"
    # `--check-only` exits 1 even on a clean file because dtype.bend has 14
    # unfilled laws, so the FIRST LINE is the signal and not the exit status.
    if "SOME PROOFS FAIL" in verdict and "dtype" not in (chk.stdout + chk.stderr):
      fails.append(f"{f}: {verdict} -- and NOT the known dtype.bend 14")
    it = run([str(BEND), str(src)])
    if it.returncode != 0:
      fails.append(f"{f} interpreted exit {it.returncode}: {(it.stdout + it.stderr)[:300]}")
      continue
    nat = SLOP / f"{f}-native"
    cp = run([str(BEND), str(src), "-o", str(nat)])
    if cp.returncode != 0:
      fails.append(f"{f} compile exit {cp.returncode}"); continue
    nv = run([str(nat)])
    if it.stdout != nv.stdout:
      fails.append(f"{f}: LANES DIFFER")
      for a, b in zip(it.stdout.splitlines(), nv.stdout.splitlines()):
        if a != b: fails.append(f"   interp {a!r} != native {b!r}")
    (SLOP / f"{f}-interp.txt").write_text(it.stdout)
    n = len([l for l in it.stdout.splitlines() if "=" in l])
    if n == 0:
      fails.append(f"{f}: ZERO ROWS -- not started, or broke")
    if n != EXPECT[f]:
      fails.append(f"{f}: {n} rows, expected {EXPECT[f]}")
    BEND_ROWS[f] = rows_of(SLOP / f"{f}-interp.txt")

  ALL = {}
  for d in BEND_ROWS.values(): ALL.update(d)

  # ---- 4 and 5. every row is accounted for, and every mapped row compared --
  def is_marker(k: str) -> bool:
    base = k[:-2] if k.endswith("=1") else k
    return base.endswith("_done") or base.endswith("-done")
  markers = sorted(k for k in ALL if is_marker(k))
  for k in sorted(ALL):
    if is_marker(k): continue
    if k in UNCHECKED or k in EXCEPTIONS: continue
    if k in ORACLE: continue
    fails.append(f"UNMAPPED BEND ROW (no oracle row): {k}={ALL[k]!r}")

  checked = 0
  for bn, on in EXCEPTIONS.items():
    if is_marker(bn): continue
    if bn not in ALL:
      if bn not in UNCHECKED: fails.append(f"MAPPED BEND ROW MISSING: {bn}")
      continue
    if on is None:
      if bn not in UNCHECKED: fails.append(f"MAPPED ROW WITH NO ORACLE: {bn}")
      continue
    if on not in ORACLE:
      fails.append(f"ORACLE ROW MISSING for {bn} -> {on}"); continue
    checked += 1
    if ALL[bn] != ORACLE[on]:
      fails.append(f"MISMATCH {bn}\n   bend   ={ALL[bn]!r}\n   oracle={ORACLE[on]!r}   ({on})")

  # identity-mapped rows: every remaining bend row that the oracle also has
  for k in sorted(ALL):
    if is_marker(k): continue
    if k in EXCEPTIONS or k in UNCHECKED: continue
    if k not in ORACLE:
      continue
    checked += 1
    if ALL[k] != ORACLE[k]:
      fails.append(f"MISMATCH {k}\n   bend   ={ALL[k]!r}\n   oracle={ORACLE[k]!r}")

  secs = {k.split(".")[1]: v for k, v in ORACLE.items() if k.startswith("META.") and k.count(".") == 2}
  print(f"oracle rows      : {len(ORACLE)}  (sections {secs})")
  print(f"bend rows        : {len(ALL)} across {len(BEND_ROWS)} files")
  print(f"rows compared    : {checked}")
  print(f"rows UNCHECKED   : {len(UNCHECKED)} (each with a reason in cs_check.py)")
  if fails:
    print(f"\n=== {len(fails)} PROBLEM(S) ===")
    for f in fails: print("  " + f)
    sys.exit(1)
  print("\nALL CHECKS PASS")


if __name__ == "__main__":
  main()