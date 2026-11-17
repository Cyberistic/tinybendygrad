import json
import pathlib
import sys
import time

sys.path.insert(0, '.agents/slop/cpuseam'); sys.path.insert(0, '.agents/slop/cpuseam/builds')
import noisefloor  # noqa: E402

B = pathlib.Path('.agents/slop/cpuseam/builds')

# **THE **ROWS.get **CALLS**, **WITH **THE **INDEX**, **THE **BLOCK's **LENGTH**, **THE **OFFSET
# **THAT **`Rows.get` **ITSELF **COMPUTED** (NOT **A **SECOND **CALL**), **AND **THE **RESULT** --
# **⇒⇒⇒ AND **THE **OFFSET **MUST **BE **READ **FROM **THE **COMPILED **`Rows.get`'s **OWN
# **LOCAL** (`_x_0`**), **⇒⇒⇒ AND **A **PROBE **THAT **RE-COMPUTES **IT **IS **MEASURING **A
# **DIFFERENT **THING****.


def instrument(js_path, out_path):
    src = pathlib.Path(js_path).read_text()
    name = "$_________tinybendygrad_renderer_cstyle_Rows_get"
    site = f"function {name}("
    if src.count(site) != 1:
        raise SystemExit(f"WARN: the Rows_get site is {src.count(site)}")
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
    # **⇒⇒⇒ AND **THE **INDEX **PARAMETER **IS **THE **SECOND** ONE** (`_r_0` **IS **THE **ROWS**),
    # **⇒⇒⇒ AND **THE **FIRST **ONE **WAS **LOGGED** -- **⇒⇒⇒ AND **THAT **IS **WHY **THE
    # **TRACE **PRINTED **"Rows"** (THE **ROWS' **TAG**)**.
    idx_param = params.split(",")[1].strip()
    # **THE **PROBE**: **REPLACE **THE **RETURN **WITH **ONE **THAT **RECORDS **THE **OFFSET
    # **THE **FUNCTION **ITSELF **COMPUTED** (`_x_0`) **AND **THE **RESULT**.
    old_tail = 'return $Maybe_default($$List_get(_b_0, (_x_0 )), {$: "Nil"});'
    if src.count(old_tail) != 1:
        raise SystemExit(f"WARN: the return site is {src.count(old_tail)}")
    new_tail = ("const __rr = $Maybe_default($$List_get(_b_0, (_x_0 )), {$: \"Nil\"}); "
                "if (globalThis.__RG && globalThis.__RG.n < 10) { "
                "globalThis.__RG.rows.push({i: " + idx_param + ", off: _x_0, r: __rr}); "
                "globalThis.__RG.n += 1; } return __rr;")
    src = src.replace(old_tail, new_tail, 1)
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
    """**⇒⇒⇒ AND **THE **JSON **FORM **OF **A **U32 **IS **`{"$": "Some", "value": N}`** (THE
    **RUNTIME's **BOX**)** -- **⇒⇒⇒ AND **THE **OLD **PROBE **RETURNED **THE **TAG** (THE
    **"Rows"** IN **THE **TRACE** WAS **THE **TAG**)**."""
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


for js, out in [("now.js", "r_old.js"), ("now_fwd.js", "r_new.js")]:
    instrument(B / js, B / out)
    d = noisefloor.Daemon(B / out, "rows")
    d.start()
    time.sleep(0.8)
    d.turn()
    d.stop()
    R = json.loads((B.parent / "nf-rows/cpu.json.d").read_text())
    print(f"=== {js}: THE Rows.get CALLS ===")
    for r in R.get("rows", [])[:8]:
        print(f"  i={scalar(r.get('i'))} off={scalar(r.get('off'))} "
              f"THE RESULT={pieces(r.get('r'))}")
    print()
