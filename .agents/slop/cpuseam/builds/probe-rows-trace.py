import json
import pathlib
import sys
import time

sys.path.insert(0, '.agents/slop/cpuseam'); sys.path.insert(0, '.agents/slop/cpuseam/builds')
import noisefloor  # noqa: E402

B = pathlib.Path('.agents/slop/cpuseam/builds')

# **THE **VALUES **THAT **`Rows.get`**'s **OWN **READS **PRODUCE**, FOR **THE **FIRST **FEW
# **CALLS**: **THE **INDEX**, **THE **BLOCK **INDEX**, **THE **BLOCK's **LENGTH**, **THE
# **OFFSET**, **AND **THE **RESULT** -- **⇒⇒⇒ AND **THE **BLOCK's **LENGTH** IS **WHAT **SAYS
# **WHETHER **THE **OFFSET **IS **IN **RANGE**.


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
    idx_param = params.split(",")[0].strip()
    # **THE **PROBE**: **RECORD **THE **BLOCK's **LENGTH** (THE **WALK **OF **THE **BLOCK**),
    # **THE **BI**, **THE **OFFSET**, **AND **THE **RESULT**.
    probe = ("\n  const __blen = (() => { let __n = 0, __x = _b_0; "
             "while (__x && __x.$ === \"Con\") { __n += 1; __x = __x.tail; } return __n; })();"
             "\n  const __v = (() => { const __r = "
             "$Maybe_default($$List_get(_b_0, (_x_0 )), {$: \"Nil\"}); "
             "if (globalThis.__RG && globalThis.__RG.n < 8) { "
             "globalThis.__RG.rows.push({i: " + idx_param + ", bi: $$"
             "_________tinybendygrad_renderer_cstyle_Rows_bi(_r_0, " + idx_param + "), "
             "off: $$_________tinybendygrad_renderer_cstyle_Rows_off(_r_0, " + idx_param + "), "
             "blen: __blen, r: __r}); globalThis.__RG.n += 1; } "
             "return __r; })();")
    old_tail = 'return $Maybe_default($$List_get(_b_0, (_x_0 )), {$: "Nil"});'
    if src.count(old_tail) != 1:
        raise SystemExit(f"WARN: the return site is {src.count(old_tail)}")
    src = src.replace(old_tail, probe + "\n  return __v;", 1)
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
        return x.get("value", x.get("$"))
    return x


for js, out in [("now.js", "probe_old.js"), ("now_fwd.js", "probe_new.js")]:
    instrument(B / js, B / out)
    d = noisefloor.Daemon(B / out, "probe")
    d.start()
    time.sleep(0.8)
    d.turn()
    d.stop()
    R = json.loads((B.parent / "nf-probe/cpu.json.d").read_text())
    print(f"=== {js} ===")
    for r in R.get("rows", [])[:6]:
        pieces = r.get("r")
        if isinstance(pieces, dict) and pieces.get("$") == "Con":
            ps = [pieces.get("head")]
        else:
            ps = []
        print(f"  i={scalar(r.get('i'))} bi={scalar(r.get('bi'))} off={scalar(r.get('off'))} "
              f"THE BLOCK's LENGTH={scalar(r.get('blen'))} FIRST PIECE={ps}")
    print()
