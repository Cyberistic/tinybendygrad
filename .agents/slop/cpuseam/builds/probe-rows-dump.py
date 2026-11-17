import json
import pathlib
import sys
import time

sys.path.insert(0, '.agents/slop/cpuseam'); sys.path.insert(0, '.agents/slop/cpuseam/builds')
import noisefloor  # noqa: E402

B = pathlib.Path('.agents/slop/cpuseam/builds')

# **THE **WHOLE **ROWS' **STRUCTURE**, **FLATTENED**: **FOR **EACH **BLOCK**, **FOR **EACH **ROW**,
# **THE **ROW's **PIECES** -- **⇒⇒⇒ AND **THIS **IS **THE **DIRECT **DUMP** THAT **SHOWS **WHERE
# **THE **MISSING `2`** **IS**.


def instrument(js_path, out_path):
    src = pathlib.Path(js_path).read_text()
    name = "$_________tinybendygrad_renderer_cstyle_Rows_blk"
    site = f"function {name}("
    if src.count(site) != 1:
        raise SystemExit(f"WARN: the Rows_blk site is {src.count(site)}")
    i = src.index(site)
    b = src.index("{", i)
    # **THE **DUMP**: **THE **WHOLE **LIST**, **AS **AN **ARRAY **OF **ARRAYS** (THE **JSON **CAN
    # **CARRY **THE **NESTED **LISTS**)**.
    probe = ('\n  { const __ls = []; let __x = _r_0.ts; '
             'while (__x && __x.$ === "Con") { const __rs = []; let __y = __x.head; '
             'while (__y && __y.$ === "Con") { const __ps = []; let __z = __y.head; '
             'while (__z && __z.$ === "Con") { __ps.push(__z.head); __z = __z.tail; } '
             '__rs.push(__ps); __y = __y.tail; } __ls.push(__rs); __x = __x.tail; } '
             'if (globalThis.__RG) { globalThis.__RG.rows = __ls; globalThis.__RG.n += 1; } }')
    src = src[:b + 1] + probe + src[b + 1:]
    old2 = "function $serve(_fuel_0, _m_0, _s_0) {"
    src = src.replace(old2, "globalThis.__RG = {rows: [], n: 0};\n" + old2, 1)
    old3 = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
    new3 = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__RG || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
    if src.count(old3) != 1:
        raise SystemExit(f"WARN: the @@END site is {src.count(old3)}")
    src = src.replace(old3, new3, 1)
    pathlib.Path(out_path).write_text(src)


for js, out in [("now.js", "d_old.js"), ("now_fwd.js", "d_new.js")]:
    instrument(B / js, B / out)
    d = noisefloor.Daemon(B / out, "dump")
    d.start()
    time.sleep(0.8)
    d.turn()
    d.stop()
    R = json.loads((B.parent / "nf-dump/cpu.json.d").read_text())
    blocks = R.get("rows", [])
    print(f"=== {js}: {len(blocks)} BLOCKS ===")
    # **THE **FIRST **BLOCK, **THE **FIRST **FEW **ROWS** -- **⇒⇒⇒ AND **THE **ROWS **WITH **THE
    # **LITERAL `2`** (THE **OUTPUT's **MISSING **CONSTANT**)**.
    # **⇒⇒⇒ AND **THE **WHOLE **LIST**, **FLATTENED**, **SO **THE **TWO **BUILDS' **SEQUENCES
    # **CAN **BE **COMPARED **DIRECTLY** -- **⇒⇒⇒ AND **THE **SEQUENCE **IS **WHAT **THE
    # **RENDER **READS** (ROW **BY **ROW**)**.
    flat = []
    for block in blocks:
        for row in block:
            flat.append(row)
    print(f"  THE FLAT SEQUENCE, {len(flat)} ROWS:")
    for ri, row in enumerate(flat[:14]):
        print(f"    ROW {ri}: {row}")
    print()
