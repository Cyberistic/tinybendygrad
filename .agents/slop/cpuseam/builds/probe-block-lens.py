import json
import pathlib
import sys
import time

sys.path.insert(0, '.agents/slop/cpuseam'); sys.path.insert(0, '.agents/slop/cpuseam/builds')
import noisefloor  # noqa: E402

B = pathlib.Path('.agents/slop/cpuseam/builds')

# **THE **BLOCK **LENGTHS**, **IN **ORDER**, IN **BOTH **BUILDS** -- **⇒⇒⇒ AND **THAT **IS **THE
# **LAYOUT** (THE **PARTIAL **BLOCK's **POSITION** AND **THE **FULL **ONES**)****.


def instrument(js_path, out_path):
    src = pathlib.Path(js_path).read_text()
    name = "$_________tinybendygrad_renderer_cstyle_Rows_blk"
    site = f"function {name}("
    if src.count(site) != 1:
        raise SystemExit(f"WARN: the Rows_blk site is {src.count(site)}")
    i = src.index(site)
    op = src.index("(", i)
    d = 0
    for c in range(op, len(src)):
        if src[c] == "(":
            d += 1
        elif src[c] == ")":
            d -= 1
            if d == 0:
                cp = c
                break
    # **THE **WHOLE **BLOCK LIST's **LENGTHS**, READ **AT **`Rows.blk`**'s **ENTRY** (WHERE **THE
    # **ROWS **ARE **IN **SCOPE**)****.
    probe = ("\n  { let __n = 0, __x = _r_0.ts; const __ls = []; "
             "while (__x && __x.$ === \"Con\") { let __m = 0, __y = __x.head; "
             "while (__y && __y.$ === \"Con\") { __m += 1; __y = __y.tail; } "
             "__ls.push(__m); __n += 1; __x = __x.tail; } "
             "if (globalThis.__RG) { globalThis.__RG.lens = __ls; globalThis.__RG.n += 1; } }")
    src = src[:i + src[i:].index("{")] + src[i + src[i:].index("{"):]
    # **INSERT **THE **PROBE **RIGHT **AFTER **THE **OPENING **BRACE****.
    b = src.index("{", i)
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


for js, out in [("now.js", "lens_old.js"), ("now_fwd.js", "lens_new.js")]:
    instrument(B / js, B / out)
    d = noisefloor.Daemon(B / out, "lens")
    d.start()
    time.sleep(0.8)
    d.turn()
    d.stop()
    R = json.loads((B.parent / "nf-lens/cpu.json.d").read_text())
    lens = R.get("lens", [])
    # **⇒⇒⇒ AND **THE **DUMP **IS **THE **LAST **CALL's **STATE** (THE **ACCUMULATOR **IS
    # **OVERWRITTEN **EVERY **CALL**) -- **⇒⇒⇒ AND **THE **LAST **CALL **IS **THE **BIG
    # **KERNEL** (THE **RENDER **ENDS **WITH **IT**)****.
    print(f"=== {js}: THE BLOCK LENGTHS ({len(lens)} blocks) ===")
    print(f"  {lens[:12]} ... {lens[-6:]}")
    print(f"  THE SUM: {sum(lens)}   THE PARTIAL ONES: "
          f"{[(i, l) for i, l in enumerate(lens) if l != 16]}")
    print()
