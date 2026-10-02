"""THE MUTATION TABLE for the ops_cl -> {ops_cl, ops_cuda, ops_hip} SPLIT.

A gate that a split did not move is a gate that cannot see the split. Each entry
below edits ONE thing in a scratch copy of ONE of the three files, reruns the
three files, and counts how many `name=value` LINES differ -- whole lines, not row
names, because a name-comparing harness reported 0 for all 68 mutations in one
unit and 0 for all 30 in another.

  python3 .agents/slop/cl_split_mutate.py
"""
import pathlib, re, shutil, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
BEND = ROOT / "bin/bend"
FILES = ["ops_cl", "ops_cuda", "ops_hip"]

# (id, file, what, old, new, kind) -- kind is "theorem" or "blind spot" for a zero.
MUTS = [
  ("M1", "ops_cuda", "vend.cu: swap cells 19 and 20 (cuMemAlloc_v2 / cuMemHostAlloc)",
   '"cuMemAlloc_v2", "cuMemHostAlloc",', '"cuMemHostAlloc", "cuMemAlloc_v2",'),
  ("M2", "ops_cuda", "cu.free.at: drop the cuCtxSynchronize before the free",
   "cu.free.at(spec.is_host(s), buf, buf, cu.sync(t))", "cu.free.at(spec.is_host(s), buf, buf, t)"),
  ("M3", "ops_cuda", "Spec: swap the host and cpu fields",
   "Spec{host: Bool, cpu: Bool, ext: U32}", "Spec{cpu: Bool, host: Bool, ext: U32}"),
  ("M4", "ops_cuda", "cu.kernarg_extra: drop the 40-byte descriptor offset",
   "def cu.kernarg_extra(blob_after: U32) -> U32: U32.sub(blob_after, CU_DESC_OFF())",
   "def cu.kernarg_extra(blob_after: U32) -> U32: blob_after"),
  ("M5", "ops_hip", "vend.hp: typo a symbol (hipMalloc -> hipMallocX)",
   '"hipMalloc"', '"hipMallocX"'),
  ("M6", "ops_hip", "hp_err_of: change the message prefix",
   'String.concat(["HIP Error ", CL.u32s(status), ", "])',
   'String.concat(["H1P Error ", CL.u32s(status), ", "])'),
  ("M7", "ops_hip", "vend.checked: forget hp_unchecked (hipEventCreate IS checked)",
   "def vend.checked(+op: U32) -> Bool: Bool.not(CL.is_unchecked(hp_unchecked(), op))",
   "def vend.checked(+op: U32) -> Bool: True{}"),
  ("M8", "ops_hip", "timing.scale_hp: hp:57's 1e-3 -> 1e-2",
   "def timing.scale_hp() -> F32: 0.001", "def timing.scale_hp() -> F32: 0.01"),
  ("M9", "ops_hip", "t_cross: swap the second and third cells of x_launch",
   "CL.vend.name(CL.OP_LAUNCH()), CU.vend.name(CL.OP_LAUNCH()),\n      vend.name(CL.OP_LAUNCH())",
   "vend.name(CL.OP_LAUNCH()), CU.vend.name(CL.OP_LAUNCH()),\n      CL.vend.name(CL.OP_LAUNCH())"),
  ("M10", "ops_cl", "cl_err_msg: spell the tag wrong (CL_SUCCESS -> CL_SUCESS)",
   '"OpenCL Error "', '"0penCL Error "'),
  ("M11", "ops_cl", "V_CL: shift the Prog unit tag",
   "def V_CL() -> U32: 0", "def V_CL() -> U32: 1"),
  ("M12", "ops_cl", "cl.pitch: halve the pitch alignment",
   "def cl.PITCH_ALIGN() -> U32: 256", "def cl.PITCH_ALIGN() -> U32: 128"),
  ("M13", "ops_cl", "TYPE-DECLARATION field order: swap Sig's `h` and `w`",
   "Sig{slot: U32, bits: U32, isz: U32, isimg: Bool, h: U32, w: U32}",
   "Sig{slot: U32, bits: U32, isz: U32, isimg: Bool, w: U32, h: U32}"),
  ("M14", "ops_hip", "TRAP: a STRING LITERAL, the tc_ptx bug's exact class -- a",
   '"hipModuleLaunchKernel"', '"T.r1_ModuleLaunchKernel"'),
  ("M15", "ops_cl", "TRAP: a string literal in the OPENCL table",
   '"clEnqueueNDRangeKernel"', '"T.r1_NDRangeKernel"'),
  ("M16", "ops_cl", "READER binding: swap Sig.w and Sig.h (the ops_cl Sig inversion,",
   "def Sig.w(+s: Sig) -> U32:\n  match s:\n    case Sig{slot, bits, isz, isimg, h, w}: w",
   "def Sig.w(+s: Sig) -> U32:\n  match s:\n    case Sig{slot, bits, isz, isimg, h, w}: h"),
  ("M17", "ops_cuda", "Spec.of: swap the host and cpu ARGUMENTS (the constructor,",
   "def Spec.of(host: Bool, cpu: Bool, ext: U32) -> Spec: Spec{host, cpu, ext}",
   "def Spec.of(host: Bool, cpu: Bool, ext: U32) -> Spec: Spec{cpu, host, ext}"),
]


def rows(root: pathlib.Path) -> list[str]:
  """run the three files. A ZERO-row file is a FAILURE, not a result: bend 2.0.34
  stack-overflows about one run in twenty, and a 0-row run diffed against 445
  reports all 445 as moved, which is how an oracle that emitted nothing and
  exited 1 once got read as a passing gate."""
  out = []
  for f in FILES:
    got = []
    for _ in range(5):
      r = subprocess.run([BEND, root / f"tinybendygrad/runtime/{f}.bend"],
                         capture_output=True, text=True)
      got = [ln for ln in r.stdout.splitlines() if "=" in ln]
      if got:
        break
    if not got:
      sys.exit(f"  !! {f}.bend printed ZERO rows after 5 attempts. That is the "
               f"machine stack overflow, not a result. Rerun the mutation.")
    out += got
  return out


with tempfile.TemporaryDirectory() as td:
  base = pathlib.Path(td) / "base"
  shutil.copytree(ROOT / "tinybendygrad", base / "tinybendygrad")
  ref = rows(base)
  assert len(ref) == 445, f"baseline printed {len(ref)} rows, not 445 -- rerun"
  print(f"baseline: 445 rows\n")
  print("a mutation of N rows with `d(rows)=0` is a TRAP-CLASS RESULT, not a")
  print("vacuuous one: it is a string literal whose text changed while the row")
  print("COUNT stayed 445. A harness that diffed row NAMES would report nothing.")
  print()
  print(f"{'id':4} {'file':9} {'lines':>5} {'d(rows)':>7}  moved-by-name")
  print("-" * 100)
  for mid, f, why, old, new in MUTS:
    p = base / f"tinybendygrad/runtime/{f}.bend"
    src = p.read_text()
    if old not in src:
      print(f"{mid:4} {f:9} {'--':>5} {'--':>7}  ANCHOR NOT FOUND -- stale mutation")
      continue
    p.write_text(src.replace(old, new, 1))
    got = rows(base)
    p.write_text(src)
    a = {ln.split("=", 1)[0]: ln for ln in ref}
    b = {ln.split("=", 1)[0]: ln for ln in got}
    moved = sorted(n for n in set(a) | set(b) if a.get(n) != b.get(n))
    print(f"{mid:4} {f:9} {len(moved):>5} {len(got) - len(ref):>+7}  {why}")
    print(f"{'':4} {'':9} {'':>5} {'':>7}  moved: {', '.join(moved) if moved else 'NOTHING'}")
  print("-" * 100)
  print("every mutation above is applied to a scratch copy under $TMPDIR and reverted;")
  print("the three files in the working copy are untouched.")