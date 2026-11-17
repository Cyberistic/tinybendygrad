import json
import pathlib
import sys
import time

sys.path.insert(0, '.agents/slop/cpuseam'); sys.path.insert(0, '.agents/slop/cpuseam/builds')
import noisefloor  # noqa: E402

B = pathlib.Path('.agents/slop/cpuseam/builds')

# **THE **PIECES **OF **ROW `i`**, FOR **A **FEW **i`s**, IN **BOTH **BUILDS** -- **⇒⇒⇒ AND **THE
# **DIFFERENCE **IS **WHERE **THE **LAYOUT **DIVERGES**.
#
# **⇒⇒⇒ AND **THE **PROBE **PATCHES **`Rows.get`** TO **RECORD **THE **RESULT** FOR **A **FEW
# **INDICES** -- **⇒⇒⇒ AND **THE **RESULT **IS **THE **LIST **OF **PIECES** (THE **NAMES**)****.


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
    brace = src.index("{", cp)
    # **THE **PROBE**: **RECORD **THE **RESULT **FOR **THE **FIRST **FEW **CALLS**, **WITH **THE
    # **INDEX****.
    # **⇒⇒⇒ AND **THE **INDEX **PARAMETER's **NAME **IS **READ **FROM **THE **COMPILED FORM**
    # (MEASURED: **THE **OLD **BUILD's **PARAMETER **IS **`_d_0`** AND **THE **NEW **ONE's **IS
    # **`_i_0`**, **AND **A **HARDCODED **NAME **IS **A ReferenceError**)**.
    idx_param = src[op + 1:cp].split(",")[0].strip()
    probe = ("\n  const __v = (() => { const __r = "
             "$Maybe_default($$List_get(_b_0, (_x_0 )), {$: \"Nil\"}); "
             "if (globalThis.__RG && globalThis.__RG.n < 12) { "
             "globalThis.__RG.rows.push([" + idx_param + ", __r]); globalThis.__RG.n += 1; } "
             "return __r; })();")
    # **THE **ORIGINAL **BODY** IS **REPLACED** -- **⇒⇒⇒ AND **THE **ORIGINAL **RETURN **IS
    # **KEPT** (THE **PROBE **RETURNS **THE **SAME **VALUE**)****.
    old_tail = 'return $Maybe_default($$List_get(_b_0, (_x_0 )), {$: "Nil"});'
    if src.count(old_tail) != 1:
        raise SystemExit(f"WARN: the return site is {src.count(old_tail)}")
    src = src.replace(old_tail, probe + "\n  return __v;", 1)
    # **THE **ACCUMULATOR**.
    old2 = "function $serve(_fuel_0, _m_0, _s_0) {"
    src = src.replace(old2, "globalThis.__RG = {rows: [], n: 0};\n" + old2, 1)
    # **THE **DUMP**.
    old3 = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
    new3 = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__RG || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
    if src.count(old3) != 1:
        raise SystemExit(f"WARN: the @@END site is {src.count(old3)}")
    src = src.replace(old3, new3, 1)
    pathlib.Path(out_path).write_text(src)


def flat(x):
    """**THE **PIECES**, **AS **A **LIST** OF **STRINGS** -- **⇒⇒⇒ AND **THE **JSON **ROUND
    TRIP **TURNS **THE **LIST **INTO **A **DICT** (THE **INDEXES **ARE **THE **KEYS**), **⇒⇒⇒ AND
    **SO **THE **FLATTENER **HANDLES **BOTH** (MEASURED: **THE **FIRST **FORM **RAISED **"TypeError:
    unsupported format string passed to dict.__format__"**)****."""
    out = []
    if isinstance(x, dict):
        if x.get("$") != "Con":
            return []
        out.append(x.get("head"))
        x = x.get("tail")
    elif isinstance(x, list):
        # **THE **JSON **FORM**: **A **LIST **OF **THE **PIECES** -- **⇒⇒⇒ AND **THE **FIRST
        # **ELEMENT **IS **THE **HEAD** **AND **THE **REST **IS **THE **TAIL** AS **A **LIST****.
        return list(x)
    while isinstance(x, dict) and x.get("$") == "Con":
        out.append(x.get("head"))
        x = x.get("tail")
    return out


for js, out in [("now.js", "probe_old.js"), ("now_fwd.js", "probe_new.js")]:
    instrument(B / js, B / out)
    d = noisefloor.Daemon(B / out, "probe")
    d.start()
    time.sleep(0.8)
    d.turn()
    d.stop()
    R = json.loads((B.parent / "nf-probe/cpu.json.d").read_text())
    print(f"=== {js}: THE FIRST CALLS INTO Rows.get ===")
    for idx, v in R.get("rows", [])[:8]:
        # **⇒⇒⇒ AND **THE **INDEX **IS **A **DICT **TOO** (THE **JSON **ROUND **TRIP**), **⇒⇒⇒
        # AND **ITS **VALUE **IS **THE **NUMBER** -- **⇒⇒⇒ AND **THE **OLD **BUILD's **INDEX **IS
        # **THE **REVERSE **INDEX** (A **DIFFERENT **NUMBER**), **⇒⇒⇒ AND **SO **THE **TWO **BUILDS'
        # **FIRST **CALLS **ARE **AT **DIFFERENT **ROW **INDICES** -- **⇒⇒⇒ AND **THAT **IS
        # **EXPECTED** (THE **NEW **ONE **IS **FORWARD**)**.
        iv = idx.get("value") if isinstance(idx, dict) else idx
        print(f"  INDEX {iv}: {flat(v)}")
    print()
