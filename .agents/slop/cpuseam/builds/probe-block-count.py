import json
import pathlib
import sys
import time

sys.path.insert(0, '.agents/slop/cpuseam'); sys.path.insert(0, '.agents/slop/cpuseam/builds')
import noisefloor  # noqa: E402

B = pathlib.Path('.agents/slop/cpuseam/builds')


def instrument(js_path, out_path):
    src = pathlib.Path(js_path).read_text()
    name = "$_________tinybendygrad_renderer_cstyle_Rows_blk"
    site = f"function {name}("
    if src.count(site) != 1:
        raise SystemExit(f"WARN: the Rows_blk site is {src.count(site)}")
    i = src.index(site)
    b = src.index("{", i)
    probe = ('\n  { let __n = 0, __x = _r_0.ts; const __ls = []; '
             'while (__x && __x.$ === "Con") { let __m = 0, __y = __x.head; '
             'while (__y && __y.$ === "Con") { __m += 1; __y = __y.tail; } '
             '__ls.push(__m); __n += 1; __x = __x.tail; } '
             'if (globalThis.__RG) { globalThis.__RG.lens = __ls; '
             'globalThis.__RG.n = $$_________tinybendygrad_renderer_cstyle_Rows_n(_r_0); } }')
    src = src[:b + 1] + probe + src[b + 1:]
    old2 = "function $serve(_fuel_0, _m_0, _s_0) {"
    src = src.replace(old2, "globalThis.__RG = {lens: [], n: 0};\n" + old2, 1)
    old3 = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
    new3 = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__RG || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
    if src.count(old3) != 1:
        raise SystemExit(f"WARN: the @@END site is {src.count(old3)}")
    src = src.replace(old3, new3, 1)
    pathlib.Path(out_path).write_text(src)


def scalar(x):
    if isinstance(x, dict):
        return x.get("value", x.get("$"))
    return x


for js, out in [("now.js", "lens_old.js"), ("now_fwd.js", "lens_new.js")]:
    instrument(B / js, B / out)
    d = noisefloor.Daemon(B / out, "lens")
    d.start()
    time.sleep(0.8)
    d.turn()
    d.stop()
    R = json.loads((B.parent / "nf-lens/cpu.json.d").read_text())
    lens = R.get("lens", [])
    n = scalar(R.get("n"))
    print(f"=== {js}: n={n}, {len(lens)} BLOCKS, SUM {sum(lens)} ===")
    print(f"  THE LENGTHS: {lens[:14]} ... {lens[-5:]}")
    print()
