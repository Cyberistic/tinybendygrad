import json
import pathlib
import sys
import time

sys.path.insert(0, '.agents/slop/cpuseam'); sys.path.insert(0, '.agents/slop/cpuseam/builds')
import noisefloor  # noqa: E402

B = pathlib.Path('.agents/slop/cpuseam/builds')

# **THE **`st_set.r` **WRITES**, WITH **THE **BLOCK **INDEX**, **THE **OFFSET** **AND **THE **PIECES**
# -- **⇒⇒⇒ AND **THE **OLD **AND **NEW **BUILDS **ARE **COMPARED**, **⇒⇒⇒ AND **THE **WRITES
# **MUST **NAME **THE **SAME **ROWS**.


def instrument(js_path, out_path):
    src = pathlib.Path(js_path).read_text()
    name = "$_________tinybendygrad_renderer_cstyle_st_put_r"
    site = f"function {name}("
    if src.count(site) != 1:
        raise SystemExit(f"WARN: the st_put_r site is {src.count(site)}")
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
    params = src[op + 1:cp]
    # **THE **PARAMETERS**: `_ps_0, _n_0, _mode_0, _st_0`.
    names = [x.strip() for x in params.split(",")]
    ps, n, mode = names[0], names[1], names[2]
    # **THE **PROBE**: **RECORD **THE **MODE**, **THE **ROW **COUNT** **AND **THE **PIECES**.
    brace = src.index("{", cp)
    probe = (f"\n  if (globalThis.__RG && globalThis.__RG.n < 30) {{ "
             f"globalThis.__RG.rows.push({{mode: {mode}, n: {n}, ps: {ps}}}); "
             f"globalThis.__RG.n += 1; }}")
    src = src[:brace + 1] + probe + src[brace + 1:]
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


def scalar(x):
    if isinstance(x, dict):
        if x.get("$") == "Some":
            return x.get("value")
        if x.get("$") == "Nil":
            return "NIL"
        return x.get("$")
    return x


def pieces(x):
    out = []
    while isinstance(x, dict) and x.get("$") == "Con":
        out.append(x.get("head"))
        x = x.get("tail")
    return out


for js, out in [("now.js", "p_old.js"), ("now_fwd.js", "p_new.js")]:
    instrument(B / js, B / out)
    d = noisefloor.Daemon(B / out, "put")
    d.start()
    time.sleep(0.8)
    d.turn()
    d.stop()
    R = json.loads((B.parent / "nf-put/cpu.json.d").read_text())
    print(f"=== {js}: THE st_put.r CALLS ===")
    for r in R.get("rows", [])[:12]:
        print(f"  mode={scalar(r.get('mode'))} n={scalar(r.get('n'))} "
              f"THE PIECES={pieces(r.get('ps'))}")
    print()
