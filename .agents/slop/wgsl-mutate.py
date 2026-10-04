#!/usr/bin/env python3
"""The mutation driver for tinybendygrad/renderer/wgsl.bend.

Each mutation is ONE textual edit to the file, run one at a time, and the rows
are diffed against the unmutated output. A row that only ONE mutation moves is a
LOCALISED row; a mutation that moves nothing is a blind spot, and both facts go
in the table at the foot of the file.

    python3 .agents/slop/wgsl-mutate.py
"""
import os
import subprocess
import sys
import tempfile
import patch_not_apply as PNA

# One format for every row this table prints, with the count column as wide as
# the marker: a column too narrow for its own refusal shifts `rows` sideways.
ROW = "%-5s %-*s %s"

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TARGET = os.path.join(ROOT, "tinybendygrad", "renderer", "wgsl.bend")
BEND = os.path.join(ROOT, "bin", "bend")

# (id, what the mutation breaks, old, new)
MUTATIONS = [
    # -- the predicate the gate was MISSING a row for, and the one that was
    # -- actually inverted while this file was written.
    ("M1", "is_packed ANDs addr_is_reg instead of negating it (the shipped bug)",
     "Bool.not(addr_is_reg(addr)))", "addr_is_reg(addr))"),
    ("M2", "is_packed drops the `dt != half` clause",
     "Bool.not(O.eq_dt(dt, S.half()))", "True{}"),
    ("M3", "is_packed drops the `itemsize < 4` clause",
     "U32.is_lt(S.Dt.itemsize(dt), 4)", "True{}"),
    # -- the two folds whose constructor decides the ORDER of a whole shader.
    ("M4", "bd_go conses instead of appends, reversing every binding",
     "List.append(&2, String, acc, [bd_one(h, k)]))", "bd_one(h, k) <> acc)"),
    ("M5", "pt.go appends instead of conses, reversing the kernel body",
     "List.append(&2, String, Part.rest(acc), [h])}", "h <> Part.rest(acc)}"),
    ("M6", "u32_show appends instead of conses, reversing global_max/local_max",
     "U32.show(h) <> u32_show(t)", "List.append(&2, String, u32_show(t), [U32.show(h)])"),
    # -- the WGSL spellings, one literal at a time.
    ("M7", "the binding block gains a space before the first var<>",
     'rk_bind(Part.work(part), bufs)', 'rk_bind(Part.work(part), bufs) '),
    ("M8", "the colon after the buffer name gains a space",
     '":array<"', '": array<"'),
    ("M9", "the storage space is spelled var<storage> without read_write",
     '"var<storage,read_write>"', '"var<storage>"'),
    ("M10", "a packed buffer is not atomic",
     '"atomic<u32>", type_map(dt))', 'type_map(dt))'),
    ("M11", "atomicLoad loses its &",
     '["atomicLoad(&", x, ")"]', '["atomicLoad(", x, ")"]'),
    ("M12", "the barrier loses its trailing semicolon",
     '"workgroupBarrier();"', '"workgroupBarrier()"'),
    ("M13", "WHERE renders the ternary instead of select",
     '["select(", c, ",", b, ",", a, ")"]', '["(", a, "?", b, ":", c, ")"]'),
    ("M14", "render_cast's unsigned narrow form loses its u suffix",
     'U32.show(rc_mask(bits)), "u)"]', 'U32.show(rc_mask(bits)), ")"]'),
    ("M15", "render_cast's signed narrow form stops sign-extending",
     '")-", U32.show(rc_half(bits)), ")"]', '")+0)"]'),
    ("M16", "the f16 enablement is dropped",
     '"enable f16;\\n", "")', '"")'),
    # RE-AIMED 2026-10-04.  The old anchor carried the OPENING QUOTE, and the
    # literal grew a `@group(0) @binding(0)\n` prefix, so the quote is no longer
    # the first character of the string.  Anchoring on `var<uniform> ... f32;` is
    # the same edit at the same site: it is the one substring the mutation acts on.
    ("M17", "the INFINITY uniform is spelled with a space before the colon",
     'var<uniform> INFINITY : f32;\\n"', 'var<uniform> INFINITY:f32;\\n"'),
    ("M18", "the nan() helper is dropped from the prologue",
     'String.concat([rk_f16(Scan.half(sc)), rk_nan(), rk_inf()',
     'String.concat([rk_f16(Scan.half(sc)), rk_inf()'),
    ("M19", "the workgroup_size fallback is 0 instead of 1",
     "case Nil{}: [1]", "case Nil{}: [0]"),
    ("M20", "the local-size sort never compares, so the order is the walk order",
     "String.is_lt(Ls.nm(x), Ls.nm(h))", "False{}"),
    ("M21", "the workgroup hoisting test looks for the wrong substring",
     'String.contains(h, "var<workgroup>")', 'String.contains(h, "var<uniform>")'),
    ("M22", "the hoisted workgroup line is not lstripped",
     "[String.trim_start(h)]", "[h]"),
    ("M23", "the binding number starts at 0 instead of 1",
     "U32.show(U32.add(k, 1))", "U32.show(k)"),
    ("M24", "the vec3 builtin names lose their type",
     '"(@builtin(workgroup_id) gindex: vec3<u32>,"', '"(@builtin(workgroup_id) gindex,"'),
    ("M25", "packed_field's elems is the itemsize instead of 4/itemsize",
     "U32.div(4, S.Dt.itemsize(dt))", "S.Dt.itemsize(dt)"),
    ("M26", "packed_field's width is 4*itemsize instead of 8*itemsize",
     "U32.mul(8, S.Dt.itemsize(dt))", "U32.mul(4, S.Dt.itemsize(dt))"),
    ("M27", "wmask xors with 0 instead of 0xFFFFFFFF",
     "U32.shln(mask, U32.to_nat(shift)), 4294967295)", "U32.shln(mask, U32.to_nat(shift)), 0)"),
    ("M28", "is_nan's threshold shifts by exp instead of mant",
     "U32.to_nat(nan_m(dt)))", "U32.to_nat(nan_e(dt)))"),
    ("M29", "is_nan's mask is 2^bits instead of 2^(bits-1)",
     "Nat.sub(U32.to_nat(nan_bs(dt)), 1n)", "U32.to_nat(nan_bs(dt))"),
    ("M30", "type_map sends uchar to i32",
     "case 2 : \"u32\"", "case 2 : \"i32\""),
    # RE-AIMED 2026-10-04.  The literal moved into `wi_axis.of`, which wraps it
    # in `Some{}`, so the old anchor no longer exists.  Same site, same edit: the
    # axis letter `case 1` answers is still the thing this mutation changes.
    ("M31", "code_for_workitem's axis letter is always x",
     "case 1: Some{\"y\"}", "case 1: Some{\"x\"}"),
    ("M32", "supported_dtypes always includes half",
     "sd_go(String.contains(arch, \"shader-f16\"),", "sd_go(True{},"),
    ("M33", "_render_dtype spells the WGSL type instead of the storage class",
     'shp: List<&2, O.Sint>) -> String: "var"', 'shp: List<&2, O.Sint>) -> String: "f32"'),
    ("M34", "ssimp's CAST-of-CONST arm is dropped, so a local bound reads 0",
     "Bool.pick(U32, O.eq_op(O.Arena.op(ar, x), O.OpsCAST{}) && ss_is(ar, O.Arena.src0(ar, x)),\n      ss_of(ar, O.Arena.src0(ar, x)), 0)",
     "0"),
    ("M35", "the f16 test compares against float instead of half",
     "O.eq_dt(w_dt(ar, tb, u), S.half())", "O.eq_dt(w_dt(ar, tb, u), S.single())"),
    ("M36", "a global buffer renders as var<uniform> (the LOCAL arm taken)",
     "case S.AGlobal{}: True{}", "case S.AGlobal{}: False{}"),
]


def run(src):
    with tempfile.TemporaryDirectory() as d:
        f = os.path.join(d, "wgsl.bend")
        with open(f, "w") as h:
            h.write(src)
        # the file imports ./../uop/ops.bend etc., so it must be checked in place
        shutil_copy(f, TARGET + ".mut")
        try:
            p = subprocess.run([BEND, TARGET + ".mut", "--check-only"], capture_output=True, text=True, cwd=ROOT)
            if p.returncode != 0:
                return None, "CHECK FAIL"
            p = subprocess.run([BEND, TARGET + ".mut"], capture_output=True, text=True, cwd=ROOT)
            if p.returncode != 0:
                return None, "RUN FAIL"
            return [l for l in p.stdout.split("\n") if l.strip()], ""
        finally:
            os.remove(TARGET + ".mut")


def shutil_copy(a, b):
    with open(a) as s, open(b, "w") as d:
        d.write(s.read())


def keys(rows):
    return {r.split(" = [")[0]: r for r in rows}


def main():
    src = open(TARGET).read()
    base, err = run(src)
    if base is None:
        print("BASELINE FAILS: " + err)
        return 1
    bk = keys(base)
    print("baseline: %d rows" % len(base))
    print()
    print(ROW % ("id", len(PNA.MARKER), "moved", "rows"))
    for mid, what, old, new in MUTATIONS:
        if src.count(old) == 0:
            print(ROW % (mid, len(PNA.MARKER), PNA.not_applied(),
                         "pattern not found: " + old[:48]))
            continue
        mut = src.replace(old, new, 1)
        rows, err = run(mut)
        if rows is None:
            print(ROW % (mid, len(PNA.MARKER), "FAIL", err))
            continue
        rk = keys(rows)
        moved = [k for k in bk if k not in rk or rk[k] != bk[k]]
        print(ROW % (mid, len(PNA.MARKER), len(moved),
                     ", ".join(moved[:9]) + (" ..." if len(moved) > 9 else "")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
