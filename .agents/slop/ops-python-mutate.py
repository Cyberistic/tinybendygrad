#!/usr/bin/env python3
"""MUTATION TABLE for `tinybendygrad/runtime/ops_python.bend`'s RENDERER HALF.

One edit per mutation, applied to a scratch copy, run through the INTERPRETED
lane, and the WHOLE `name=value` LINES diffed -- not the row NAMES, because a
name-comparing harness reported 0 for all 30 mutations in one unit and 0 for all
68 in another.

    .venv/bin/python .agents/slop/ops-python-mutate.py
"""
import pathlib, re, subprocess, sys
import patch_not_apply as PNA

REPO = pathlib.Path(__file__).parent.parent.parent
# THE SUBSTRATE MIRROR, and it is not hygiene. `tinybendygrad/uop/ops.bend` was
# mid-edit by another agent while this ran -- MEASURED, three different errors from
# the same run (`b2u_of` unfilled, then `pm_scan_m` unfilled, then
# `ctx (consumed more than once)` at pm_scan_m) -- and a cold-compile failure
# naming a def that is not in this file is that agent, not this unit. So the tree is
# rebuilt from `git archive HEAD tinybendygrad` and only `runtime/ops_python.bend` is
# overlaid. Rebuild it with the command in the docstring below.
MIRROR = pathlib.Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/mirror")
TREE = MIRROR/"tinybendygrad"
SRC = TREE/"runtime"/"ops_python.bend"
SCRATCH = TREE/"runtime"/"_ops_python_mut.bend"

#   W=<scratch>; rm -rf $W; mkdir -p $W
#   git archive HEAD tinybendygrad | tar -x -C $W
#   cp tinybendygrad/runtime/ops_python.bend $W/tinybendygrad/runtime/ops_python.bend

# (id, the literal to find, the replacement, what it is testing)
MUTATIONS = [
 ("M1", 'Bool.pick(U32, U32.is_eq(tid, CORES_NONE()), 0,\n    Bool.pick(U32, U32.is_eq(tid, CORES_METAL()), 5,',
        'Bool.pick(U32, U32.is_eq(tid, CORES_NONE()), 5,\n    Bool.pick(U32, U32.is_eq(tid, CORES_METAL()), 5,',
        ":178's else arm -- `Renderer.tensor_cores` is the CLASS default [] and ncores must stay 0"),
 ("M2", 'String.eq(arch, "gfx942"), CORES_AMD_CDNA3()', 'String.eq(arch, "gfx943"), CORES_AMD_CDNA3()',
        "tc.py:98's four-key dict: gfx942 is the ONLY cdna3 key"),
 ("M3", 'Bool.or(String.eq(arch, "gfx1200"), String.eq(arch, "gfx1201")),',
        'Bool.or(String.eq(arch, "gfx1200"), String.eq(arch, "gfx1202")),',
        "the rdna4 dict has TWO keys and dropping one is a silent half-table"),
 ("M4", 'CORES_AMD_RDNA4(), CORES_AMD_RDNA3())))', 'CORES_AMD_RDNA4(), CORES_AMD_RDNA4())))',
        "get_amd's DEFAULT is amd_rdna3, so a typo'd gfx arch is a FULL rdna3 set"),
 ("M5", 'Bool.pick(U32, U32.is_ge(v, 89), CORES_CUDA_SM89(),', 'Bool.pick(U32, U32.is_ge(v, 88), CORES_CUDA_SM89(),',
        "tc.py:68's ladder is `int(arch[3:]) >= 89`, not >= 88"),
 ("M6", 'Bool.pick(U32, U32.is_ge(v, 80), CORES_CUDA_SM80(),\n      Bool.pick(U32, U32.is_ge(v, 75), CORES_CUDA_SM75(), CORES_NONE()))',
        'Bool.pick(U32, U32.is_ge(v, 80), CORES_CUDA_SM80(),\n      Bool.pick(U32, U32.is_ge(v, 75), CORES_CUDA_SM75(), CORES_METAL()))',
        "the ladder's bottom is `[]`, and a Metal table here is the fall-through value"),
 ("M7", 'String.eq(arch, "METAL"),\n      Rend{"METAL"', 'String.eq(arch, "metal"),\n      Rend{"METAL"',
        ":170's arm is `target.arch == \"METAL\"`, exactly"),
 ("M8", 'String.starts_with(arch, "gfx"),', 'String.starts_with(arch, "gfx1"),',
        ":171's `arch.startswith(\"gfx\")` -- gfx1201 is a gfx arch and must not fall to the else"),
 ("M9", 'Bool.and(image, String.eq(arch, "")),', 'Bool.and(image, String.eq(arch, "0")),',
        ":177 is `IMAGE and not target.arch`, and an EMPTY arch is the only one that qualifies"),
 ("M10", 'Rend{dev, "PYTHON", "IMAGE_PITCH_ALIGNMENT=1"', 'Rend{dev, "PYTHON", "IMAGE_PITCH_ALIGNMENT=2"',
        ":177 writes that exact arch string"),
 ("M11", 'Bool.pick(Rend, Bool.not(String.eq(emulate, "")),', 'Bool.pick(Rend, Bool.not(String.eq(emulate, "AMD")),',
        ":167's refusal is `getenv(\"EMULATE\", \"\") != \"\"` -- ANY value, not AMD's alone"),
 ("M12", 'Rend{dev, "PYTHON", arch, CORES_NONE(), 0, True{}},', 'Rend{dev, "PYTHON", arch, CORES_NONE(), 0, False{}},',
        "an EMULATE refusal is dead, so nothing about it is readable -- `bad` must be True"),
 ("M13", 'Rend{"AMD", "PYTHON", arch, a1, cores_of(a1), False{}}', 'Rend{"AMD", "PYTHON", arch, a1, 4, False{}}',
        "the AMD count comes from the TABLE the arch picked, not a constant"),
 ("M14", 'U32.is_eq(S.Dt.pri(dt), DT_F16_PRI())', 'U32.is_eq(S.Dt.pri(dt), 10)',
        "f16's priority is 12; 10 is fp8e4m3's and would drop the WRONG four dtypes"),
 ("M15", 'Bool.or(Bool.not(U32.is_eq(S.Dt.pri(dt), DT_F16_PRI())), ge312)',
         'Bool.and(Bool.not(U32.is_eq(S.Dt.pri(dt), DT_F16_PRI())), ge312)',
         ":182 is `d != half OR version >= (3,12)` -- `or`, not `and`. `and` drops every dtype on 3.11"),
 ("M16", 'Bool.and(U32.is_eq(Core.tid(c), tid),\n        Bool.and(U32.is_eq(Core.din(c), din), U32.is_eq(Core.threads(c), th))),',
         'Bool.and(U32.is_eq(Core.tid(c), tid),\n        Bool.and(U32.is_eq(Core.din(c), din), U32.is_eq(Core.threads(c), 32))),',
         "arg[:3] is (dims, dtype_in, threads); matching threads against a constant would accept a wrong warp core"),
 ("M17", 'Some{c}, core_find(t, tid, din, th))', 'core_find(t, tid, din, th))',
         ":35 is `next(...)`, so the FIRST match answers -- dropping the Some loses first-wins"),
 ("M18", 'def wma.per_msg(cc: String, want: U32, got: U32) -> String:\n  String.concat([cc,',
         'def wma.per_msg(cc: String, want: U32, got: U32) -> String:\n  String.concat(["B",',
        ":37's message names the FRAGMENT (`{cc}`), so A/B/C are three different strings"),
 ("M19", 'def wma.warp_msg(threads: U32) -> String:\n  String.concat(["must have multiples of "',
         'def wma.warp_msg(threads: U32) -> String:\n  String.concat(["must have a multiple of "',
        ":38's exact wording"),
 ("M22", 'def main.at(+a: Args) -> IO(Unit):\n  Bool.pick(IO(Unit), String.eq(Args.path(a), ""), gate(), Prog.launch.at(Some{a}))',
         'def main.at(+a: Args) -> IO(Unit):\n  Bool.pick(IO(Unit), Bool.not(String.eq(Args.path(a), "")), gate(), Prog.launch.at(Some{a}))',
         "a PACKET on the command line LAUNCHES; the empty argv runs the gate. Inverted, nothing runs"),
]


def rows_of(text):
  out = {}
  for ln in text.splitlines():
    if "=" in ln and not ln.startswith("#"):
      k, _, v = ln.partition("=")
      out[k] = v
  return out


def run(path):
  r = subprocess.run([str(REPO/"bin"/"bend"), str(path)], capture_output=True, text=True)
  return r.stdout, r.returncode


def main():
  base_out, base_rc = run(SRC)
  base = rows_of(base_out)
  assert base, "the baseline produced no rows"
  print('# baseline rows', len(base), 'rc', base_rc)
  src = SRC.read_text()
  print('# | id | edit | rows MOVED (by name) |')
  print('# | --- | --- | --- |')
  for mid, old, new, what in MUTATIONS:
    if old not in src:
      # RULE D: a patch that does not apply must never read as a zero. M4 sat in the
      # committed record as `0` for exactly this reason. PNA.not_applied() is
      # non-numeric and PNA.pipe refuses a width other than this table's 3, so
      # neither a reader scanning the count column nor one summing it can mistake
      # it for a measurement, and the figure cannot shift into another column.
      print(PNA.pipe([mid, what, PNA.not_applied('anchor not in SRC')], 3))
      continue
    SCRATCH.write_text(src.replace(old, new, 1))
    out, rc = run(SCRATCH)
    got = rows_of(out)
    moved = sorted(k for k in set(base) | set(got) if base.get(k) != got.get(k))
    # RULE B: a mutant that is not a PROGRAM says NOTHING about coverage -- not even
    # zero -- so it may not be counted in the number column.  M17 and M22 each lost
    # ALL 85 rows to a run that produced none, and the table printed `85` for both,
    # which is 170 moved rows that do not exist.
    #
    # The cell is `DID-NOT-COMPILE` and NOT `PATCH-NOT-APPLY`, because the patch DID
    # land; `DID-NOT-COMPILE` is in `zero-classify.py`'s MEASURED vocabulary and
    # classifies as NOT-A-PROGRAM, whereas the marker means "the edit never landed"
    # and would be a different, untrue statement.  It is spelled EXACTLY, with no
    # suffix: the classifier compares the whole cell and REFUSES anything else, so
    # `DID-NOT-COMPILE rc=1` would be an unrecognised measurement.  The diagnostic
    # therefore goes in the description cell, where prose already lives.
    if rc != 0 or not got:
      why = f"{what}  [rc={rc}, {len(got)} rows printed]"
      print(PNA.pipe([mid, why, PNA.not_a_program()], 3))
      continue
    print(f'| {mid} | {what} | {len(moved)} {" ".join(moved[:8]) if moved else "**NOTHING**"} |')
  SCRATCH.unlink(missing_ok=True)


if __name__ == '__main__':
  main()