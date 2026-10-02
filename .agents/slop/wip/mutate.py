"""MEASURED mutation table for tinybendygrad/renderer/cstyle.bend.

For each mutation: restore the file, apply ONE targeted edit, run the interpreted
lane, and record which rows' `[bend]` halves moved relative to the baseline.
A mutation that does not COMPILE is recorded as `NO-COMPILE` -- that is a
different outcome from "moved nothing", and both are results.

    python3 .agents/slop/wip/mutate.py            # all
    python3 .agents/slop/wip/mutate.py 03 07      # by index
"""

import re, subprocess, sys, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
BEND = os.path.join(ROOT, "bin", "bend")
SRC = os.path.join(ROOT, "tinybendygrad/renderer/cstyle.bend")
ROW = re.compile(r"^(?P<nm>.*?) = \[(?P<bend>.*)\]   py=\[(?P<py>.*)\]$")

MUTATIONS = [
 ("buffer_prefix: OpenCL `__global ` -> `__global` (drop the trailing space)",
  '    case 2: "__global "', '    case 2: "__global"'),
 ("buffer_suffix: Clang ` restrict` -> `` (drop `restrict`)",
  '    case 1: " restrict"', '    case 1: ""'),
 ("var_prefix: Metal `constant ` -> `const ` (swap a prefix clause)",
  '    case 3: "constant "', '    case 3: "const "'),
 ("var_suffix: Metal `&` -> ``",
  '    case 3: "&"', '    case 3: ""'),
 ("smem_prefix: HIP gains the trailing space that looks like a typo",
  '    case 5: "__attribute__((shared, aligned(16)))"',
  '    case 5: "__attribute__((shared, aligned(16))) "'),
 ("rd_prefix: the GLOBAL arm drops the address-space prefix",
  '    case S.AGlobal{}: buffer_prefix.of(dev)', '    case S.AGlobal{}: ""'),
 ("rd_suffix: `override_ptr` only (drop the mem-space `*`)",
  'Bool.pick(String, Bool.or(is_mem_addr(a), override_ptr), "*", "")',
  'Bool.pick(String, override_ptr, "*", "")'),
 ("has_bounds: CUDA stops substituting the bound",
  '    case 4: True{}\n    case 5: True{}\n    case _: False{}',
  '    case 4: False{}\n    case 5: True{}\n    case _: False{}'),
 ("gep_arr_threshold: CUDA 8 -> 4",
  '    case 1: 0\n    case 4: 8', '    case 1: 0\n    case 4: 4'),
 ("float4_style: Clang `{` -> `(`",
  'def float4_open(+dev: U32) -> String:\n  match dev:\n    case 1: "{"',
  'def float4_open(+dev: U32) -> String:\n  match dev:\n    case 1: "("'),
 ("code_for_clang: the ADDED `FDIV` arm is deleted",
  '    case O.OpsFDIV{}: cfo_bin(cfo_xs1(xs), "/", cfo_xs2(xs))\n    case O.OpsEXP2{}: ""',
  '    case O.OpsEXP2{}: ""'),
 ("type_map.cuda: the `float8_e4m3` entry is dropped",
  'Kv{"float8_e4m3", "__nv_fp8_e4m3", ', 'Kv{"float8_e4m3x", "__nv_fp8_e4m3", '),
 ("type_name: the `.get(dtype, dtype.name)` DEFAULT becomes empty",
  'def tm_get(+m: Map<&2, String>, +nm: String) -> Sigma<&1, &1, Map<&2, String>, _ => String>:\n  Map.get(String, nm, m, nm)',
  'def tm_get(+m: Map<&2, String>, +nm: String) -> Sigma<&1, &1, Map<&2, String>, _ => String>:\n  Map.get(String, nm, m, "")'),
 ("under: the `.replace(\" \", \"_\")` rejoin separator becomes empty",
  'case h <> t: String.concat([Bool.pick(String, seen, "_", ""), h, under_tail.go(t, True{})])',
  'case h <> t: String.concat([Bool.pick(String, seen, "", ""), h, under_tail.go(t, True{})])'),
 ("rd_body: `sz > 1` becomes `sz > 0`",
  '  Bool.pick(String, U32.is_gt(sz, 1),', '  Bool.pick(String, U32.is_gt(sz, 0),'),
 ("bt_prefix: the emitted C is `volatile_ ` instead of `volatile `",
  'Bool.pick(String, volatile_, "volatile ", "")', 'Bool.pick(String, volatile_, "volatile_ ", "")'),
 ("metal_fields: the body's mid becomes ` = args` (no dot)",
  'metal_fields(dev, bs, " = args.")', 'metal_fields(dev, bs, " = args")'),
 ("prefix_clause: HIP's `hip_bfloat16` and `#define half` swap places",
  '        case 3: inc_if(Uses.bf16(u), String.concat(["typedef ", Bool.pick(String, cdna4, "__bf16", "unsigned short"), " hip_bfloat16;"]))\n'
  '        case 4: inc_if(Uses.half(u), "#define half _Float16")',
  '        case 4: inc_if(Uses.bf16(u), String.concat(["typedef ", Bool.pick(String, cdna4, "__bf16", "unsigned short"), " hip_bfloat16;"]))\n'
  '        case 3: inc_if(Uses.half(u), "#define half _Float16")'),
 ("ocml_atr: SQRT's attribute `const` -> `pure`",
  '    case "SQRT": "const"', '    case "SQRT": "pure"'),
 ("rk_prefix: `prefix is None` becomes unconditional",
  'Bool.pick(String, has_prefix, String.concat([String.join(pref, "\\n"), "\\n", prg]), prg)',
  'String.concat([String.join(pref, "\\n"), "\\n", prg])'),
 ("is_half: CUDA's `dtype in (half, bfloat16)` drops the bfloat16 half",
  '  Bool.or(O.eq_dt(d, S.half()), O.eq_dt(d, S.bfloat16()))', '  O.eq_dt(d, S.half())'),
 ("ocml_bits: the half width 16 -> 32",
  'Bool.pick(U32, O.eq_dt(d, S.half()), 16,', 'Bool.pick(U32, O.eq_dt(d, S.half()), 32,'),
 ("prefix_clauses: CUDA's clause count 5 -> 4 (the vecs line is dropped)",
  '    case 4: 5\n    case 5: 8', '    case 4: 4\n    case 5: 8'),
 ("swizzle_char: the letter alphabet loses `abcd`",
  'String.to_list("xyzwabcd")', 'String.to_list("xyz")'),
 ("witem_xyz: `chr(120 + n)` becomes `chr(121 + n)`",
  'Char.from_u32(U32.add(120, n))', 'Char.from_u32(U32.add(121, n))'),
 ("esc_row: the GATE's own escape separator becomes `|`",
  'String.join(String.split(s, \'\\n\'), "\\\\n")', 'String.join(String.split(s, \'\\n\'), "|")'),
 ("opencl_prefix: the `#pragma` becomes unconditional",
  'def opencl_prefix(+u: Uses) -> List<&2, String>: inc_if(Uses.half(u), "#pragma OPENCL EXTENSION cl_khr_fp16 : enable")',
  'def opencl_prefix(+u: Uses) -> List<&2, String>: ["#pragma OPENCL EXTENSION cl_khr_fp16 : enable"]'),
 ("metal_body: the args line is APPENDED instead of prepended",
  '  add([String.concat(["  ", String.join(metal_fields(dev, bs, " = args."), " ")])], kernel)',
  '  add(kernel, [String.concat(["  ", String.join(metal_fields(dev, bs, " = args."), " ")])])'),
 ("ocml_extern: the attribute comma is emitted unconditionally",
  'Bool.pick(String, String.eq(ocml_atr.of(op), ""), "", ", ")', '", "'),
 ("render_buffer: the `*` in `[max_numel]` becomes a `,`",
  '"[", U32.show(numel), "];"', '"[", U32.show(numel), "],"'),
 ("extra_args: Metal's third line is dropped",
  '"uint3 lid [[thread_position_in_threadgroup]]"]', '"]"]'),
]

def run():
    r = subprocess.run([BEND, SRC], cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        return None, (r.stdout + r.stderr)
    rows = {}
    for line in r.stdout.split("\n"):
        m = ROW.match(line)
        if m:
            rows[m.group("nm")] = m.group("bend")
    return rows, None

base_src = open(SRC).read()
base, err = run()
if base is None:
    print("BASELINE DOES NOT RUN:\n" + err); sys.exit(1)
print("baseline rows: %d\n" % len(base))

want = set(sys.argv[1:])
for k, (name, old, new) in enumerate(MUTATIONS, 1):
    if want and f"{k:02d}" not in want and str(k) not in want:
        continue
    if base_src.count(old) != 1:
        print("%2d  ANCHOR-MISS(%d)  %s" % (k, base_src.count(old), name))
        continue
    open(SRC, "w").write(base_src.replace(old, new, 1))
    rows, err = run()
    if rows is None:
        verdict = "NO-COMPILE"
        moved = []
        detail = err.strip().split("\n")
        detail = " / ".join(d for d in detail if d.startswith("-") or d.startswith("Error"))[:150]
    else:
        moved = sorted(n for n in base if rows.get(n) != base[n])
        gone = sorted(set(base) - set(rows))
        verdict = "%d rows" % len(moved)
        detail = (" MISSING:" + ",".join(gone)) if gone else ""
    open(SRC, "w").write(base_src)
    print("%2d  %-12s %s" % (k, verdict, name))
    print("      rows: %s%s" % (", ".join(moved) if moved else "(none)", detail))
    if err:
        print("      %s" % detail)
print("\nbaseline restored: %s" % (open(SRC).read() == base_src))