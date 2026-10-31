#!/usr/bin/env python3
"""llm_gguf-mutate.py -- does `gates/llm_gguf-gate.py` go RED when the port is wrong?

    .venv/bin/python gates/llm_gguf-mutate.py           # measure, print the table
    .venv/bin/python gates/llm_gguf-mutate.py --write   # also write the `.rows` table

A NEW PORT HAS NO "BEFORE" TO REVERT TO, so the falsifiability question is asked the
other way: for each of the port's LOAD-BEARING decisions, put the plausible WRONG answer
in its place and measure how many rows move. A mutation that moves nothing is either a
decision the gate cannot see -- a hole, and `align_default` was one until two rows were
added for it -- or a decision that is not load-bearing, and the row count is what says
which.

EVERY MUTATION IS A SINGLE SUBSTITUTION, and each targets a wall the port's own header
names: the block geometry, the alignment (both the round-up and the default), the reader
ladder, the two 64-bit words, the sign extension, the UTF-8 width, the error spelling,
the two counts' file order, and the shape's reversal. The mutated file is restored in a
`finally`, so an interrupted run cannot leave one behind.
"""
import importlib.util
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PORT = "tinybendygrad/llm/gguf.bend"
DRIVER = "gates/llm_gguf.bend"
BEND = ROOT / "bin" / "bend"
LANE = HERE / "llm_gguf.bend"
GATE = HERE / "llm_gguf-gate.py"
PY = ROOT / ".venv" / "bin" / "python"
TABLE = HERE / "llm_gguf-mutations.rows"


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


ROWS = load("llm_gguf_fixture", "llm_gguf-fixture.py").ROWS

# (name, what the wrong version is, which file, the substring, its replacement)
MUTATIONS = (
  ("nbytes_block", "`prod//block*size` becomes `prod*size`", PORT,
   "U32.mul(U32.div(ti.prod(TIE.shape(e)), Blk.el(k)), Blk.by(k))",
   "U32.mul(ti.prod(TIE.shape(e)), Blk.by(k))"),
  ("align_roundup", "`round_up(tell(), align)` becomes `tell()`", PORT,
   "H.round_up_i32(Cur.at(c), kv.align(kvs))", "Cur.at(c)"),
  ("align_default", "the `general.alignment` default 32 becomes 16", PORT,
   "kv.align.go(kvs, 32)", "kv.align.go(kvs, 16)"),
  ("counts_order", "`n_kv` is read before `n_tensors` (`gguf.py:208` is the other way)", PORT,
   "  +t = by.t8(Cur.bs(c))\n  +c1 = cr.next(c, 8, W8.rs(t))\n  +k = by.t8(Cur.bs(c1))",
   "  +k = by.t8(Cur.bs(c))\n  +c1 = cr.next(c, 8, W8.rs(k))\n  +t = by.t8(Cur.bs(c1))"),
  ("shape_order", "the dims are NOT reversed (`gguf.py:230` reverses them)", PORT,
   "ti.dims(p, cr.next(c, 8, W8.rs(w)), W8.v(w) <> acc)",
   "ti.dims(p, cr.next(c, 8, W8.rs(w)), List.append(&2, H.I64, acc, [W8.v(w)]))"),
  ("i64_high", "the HIGH word of a u64 is dropped", PORT,
   "W8{H.i64_of_hi_lo(le4(e, f, g, h), le4(a, b, c, d)), t}",
   "W8{H.i64_of_hi_lo(0, le4(a, b, c, d)), t}"),
  ("sx8", "`struct`'s \"b\" is read unsigned", PORT,
   "Bool.pick(U32, U32.is_ge(b, 128), U32.or(b, 4294967040), b)", "b"),
  ("utf8_width", "a 4-byte UTF-8 lead is read as 3 bytes", PORT,
   "Bool.pick(Nat, U32.is_lt(b, 240), 2n, 3n)", "Bool.pick(Nat, U32.is_lt(b, 248), 2n, 3n)"),
  ("fmt_ladder", "`readers[2]` answers the ARRAY reader (a transcription slip)", PORT,
   "    case 2: Some{FU16{}}", "    case 2: Some{FArr{}}"),
  ("nat_ladder", "`_GGML_NATIVE[24]` answers int16's itemsize", PORT,
   "    case 24: Some{1}", "    case 24: Some{2}"),
  ("qnt_table", "`_GGML_QUANT[12]` answers 160 bytes per block", PORT,
   "    case 12: Some{Blk{256, 144}}", "    case 12: Some{Blk{256, 160}}"),
  ("err_text", "`GGML type 'N' is not supported!` loses its quotes", DRIVER,
   """String.concat(["GGML type '", U32.show(typ), "' is not supported!"])""",
   """String.concat(["GGML type ", U32.show(typ), " is not supported!"])"""),
)


def lane():
    r = subprocess.run([str(BEND), str(LANE)], capture_output=True, text=True)
    return [l for l in r.stdout.splitlines() if l.strip()], r


def main():
    base, r = lane()
    if len(base) != ROWS:
        print(f"the unmutated lane emitted {len(base)} rows, not {ROWS}: {r.stderr[-400:]}")
        return 1
    source = {p: (ROOT / p).read_text() for p in (PORT, DRIVER)}
    out, holes = [], 0
    for name, why, path, old, new in MUTATIONS:
        if old not in source[path]:
            out.append(f"{name}\tMISSING\t0\t{why}")
            holes += 1
            continue
        (ROOT / path).write_text(source[path].replace(old, new, 1))
        try:
            got, _ = lane()
        finally:
            (ROOT / path).write_text(source[path])
        moved = sum(1 for a, b in zip(base, got) if a != b) + abs(len(base) - len(got))
        verdict = "RED" if (moved or len(got) != len(base)) else "GREEN"
        out.append(f"{name}\t{verdict}\t{moved}\t{why}")
        if verdict != "RED":
            holes += 1
        print(out[-1])
    if "--write" in sys.argv:
        TABLE.write_text("mutation\tverdict\trows_moved\twhy\n" + "\n".join(out) + "\n")
    print(f"-- {len(MUTATIONS)} mutations, {len(MUTATIONS) - holes} moved at least one row")

    # AND THE GATE ITSELF, on one mutation, so the table is not a claim about a lane the
    # gate might not be reading.
    name, _, path, old, new = MUTATIONS[6]
    (ROOT / path).write_text(source[path].replace(old, new, 1))
    try:
        g = subprocess.run([str(PY), str(GATE)], capture_output=True, text=True)
    finally:
        (ROOT / path).write_text(source[path])
    said = [l.strip() for l in g.stderr.splitlines() if "DISAGREE" in l]
    print(f"-- gate on the {name} mutation: rc={g.returncode} {said[:1]}")
    return 1 if holes or g.returncode == 0 else 0


if __name__ == "__main__":
    sys.exit(main())
