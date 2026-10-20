#!/usr/bin/env python3
"""BUILD `cases.rows` FROM THE CAPTURED INSTRUMENT OUTPUTS. NOTHING IS TYPED IN.

READS, ALL PRODUCED BY `collect.sh`:
  cpython.out    -- `.venv/bin/python cpython_oracle.py`   (CPython's ANSWERS)
  port.out       -- `./bin/bend probe.bend`      (THE TREE AS IT STANDS)
  port_g.out     -- `./bin/bend probe_g.bend`    (S1: + THE :389 GUARD)
  port_gw.out    -- `./bin/bend probe_gw.bend`   (S2: S1 + THE `ws[axis_w:]` TERM)
  port_gwo.out   -- `./bin/bend probe_gwo.bend`  (S3: S2 + THE TRANSPOSE AXIS)
  port_fix.out   -- `./bin/bend probe_fix.bend`  (S4: S3 + THE BROADCAST REFUSAL)
  rows_*.out     -- `./bin/bend scratch*/nn/layers.bend`  (THE FILE'S OWN ROWS)

WRITES: `cases.rows`, ONE `key=value` PER LINE, IN THE ORDER OF THE CASES.

THE PORT'S ANSWER COLUMN HAS THREE VALUES AND THE DIFFERENCE BETWEEN TWO OF
THEM IS THE WHOLE POINT:
  * A SHAPE  -- THE PORT ANSWERED.
  * `NONE`   -- THE PORT REFUSED (`nn_dot` ANSWERED `None`).
  * `<DEAD>` -- THE PORT BUILT A GRAPH WHOSE SHAPE DOES NOT FOLD. NOT A
                REFUSAL: A WRONG GRAPH HANDED BACK AS IF IT WERE AN ANSWER.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

CASES = [
    ("A", "x(2,3) . w(3,4)", 2, 2),
    ("B", "x(2,4,3) . w(3,4)", 3, 2),
    ("C", "x(8,64,7,7) . w(7,16)", 4, 2),
    ("D", "x(2,3) . w(3,)", 2, 1),
    ("P", "x(2,3) . w(4,5)", 2, 2),
    ("E", "x(2,3,4) . w(3,4,5)", 3, 3),
    ("F", "x(2,3,4) . w(3,4,1)", 3, 3),
    ("G", "x(3,3,4) . w(3,4,1)", 3, 3),
    ("H", "x(3,3,4) . w(3,5,1)", 3, 3),
    ("I", "x(3,3,4) . w(3,4,2)", 3, 3),
    ("M", "x(2,2,4) . w(3,3,4,5)", 2, 4),
    ("N", "x(2,4) . w(3,3,4,5)", 2, 4),
    ("O", "x(2,4) . w(3,3,5,5)", 2, 4),
]

EMPTY = "<DEAD>"


def read(path):
    with open(os.path.join(HERE, path), encoding="utf-8") as fh:
        return fh.read()


def cpython_rows(text):
    """`NAME -> {field: value}` FROM THE ORACLE'S OWN OUTPUT."""
    out = {}
    cur = None
    for line in text.splitlines():
        m = re.match(r"^([A-Z]): x=(\(.*?\)) w=(\(.*?\))\s*$", line.strip())
        if m:
            cur = m.group(1)
            out[cur] = {}
            out[cur]["x_shape"] = m.group(2)
            out[cur]["w_shape"] = m.group(3)
            continue
        if cur is None:
            continue
        m = re.match(r"^\s+x\.shape\s+=\s+(\(.*\))\s*$", line)
        if m:
            out[cur]["x_shape"] = m.group(1)
            continue
        m = re.match(r"^\s+w\.shape\s+=\s+(\(.*\))\s*$", line)
        if m:
            out[cur]["w_shape"] = m.group(1)
            continue
        m = re.match(r"^\s+dx,dw\s+=\s+(\d+),(\d+)\s*$", line)
        if m:
            out[cur]["dx"], out[cur]["dw"] = m.group(1), m.group(2)
            continue
        m = re.match(r"^\s+x'=\((.*?)\)\s+w'=\((.*?)\)\s+-> transposed \((.*?)\)\s*$", line)
        if m:
            out[cur]["x_target"] = "(" + m.group(1) + ")"
            out[cur]["w_target"] = "(" + m.group(2) + ")"
            out[cur]["w_permuted"] = "(" + m.group(3) + ")"
            continue
        m = re.match(r"^\s+CPYTHON: ACCEPT \((.*)\)\s+PREDICTED: ACCEPT\s*$", line)
        if m:
            out[cur]["result"] = "(" + m.group(1) + ")"
            out[cur]["refused"] = "no"
            out[cur]["mech"] = "-"
            continue
        m = re.match(r"^\s+CPYTHON: REFUSE (.*?)\s+PREDICTED: REFUSE (\w+)\s*$", line)
        if m:
            out[cur]["result"] = "RAISED " + m.group(1).strip()
            out[cur]["refused"] = "yes"
            out[cur]["mech"] = m.group(2)
            continue
    return out


def port_rows(text):
    """`A_xshape -> "2,1,3"` FROM THE PROBE'S OWN OUTPUT."""
    out = {}
    for line in text.splitlines():
        m = re.match(r"^([A-Z])_(xshape|wshape|order|result|rd)\s*=\s*(.*)$", line.strip())
        if m:
            out[f"{m.group(1)}_{m.group(2)}"] = m.group(3).strip()
    return out


def file_rows(text):
    """THE PORT'S OWN `nn_row_*` ASSERTIONS."""
    out = {}
    for line in text.splitlines():
        m = re.match(r"^(\S+)\s+got=(.*?)\s+want=(.*)$", line.strip())
        if m:
            out[m.group(1)] = (m.group(2), m.group(3))
    return out


def apply_order(shape, order):
    """THE PORT'S `wshape` WITH THE PORT'S `order` APPLIED -- THE SHAPE `w`
    IS PERMUTED TO. `order[i]` IS THE SOURCE POSITION OF THE i-th DIM."""
    if not shape or not order:
        return ""
    try:
        dims = [int(d) for d in shape.split(",")]
        return ",".join(str(dims[int(i)]) for i in order.split(","))
    except (ValueError, IndexError):
        return "?"


def main():
    out_path = sys.argv[1]
    cp = cpython_rows(read("cpython.out"))
    p0 = port_rows(read("port.out"))
    p1 = port_rows(read("port_g.out"))
    p2 = port_rows(read("port_gw.out"))
    p3 = port_rows(read("port_gwo.out"))
    p4 = port_rows(read("port_fix.out"))
    f0 = file_rows(read("rows_scratch.out"))
    f4 = file_rows(read("rows_scratchfix.out"))

    lines = [
        "# `cases.rows` -- THE `dw >= 3` ARM OF `nn_dot` (tinybendygrad/nn/layers.bend).",
        "# EVERY CELL BELOW WAS READ OUT OF AN INSTRUMENT RUN, NOT TYPED IN.",
        "#   CPython   = `.venv/bin/python .agents/slop/dw3/cpython_oracle.py`",
        "#   PORT S0   = `./bin/bend .agents/slop/dw3/probe.bend`     (THE TREE AS IT STANDS)",
        "#   PORT S1   = `./bin/bend .agents/slop/dw3/probe_g.bend`   (S0 + THE :389 GUARD)",
        "#   PORT S2   = `./bin/bend .agents/slop/dw3/probe_gw.bend`  (S1 + THE `ws[axis_w:]` TERM)",
        "#   PORT S3   = `./bin/bend .agents/slop/dw3/probe_gwo.bend` (S2 + THE TRANSPOSE AXIS)",
        "#   PORT S4   = `./bin/bend .agents/slop/dw3/probe_fix.bend` (S3 + THE BROADCAST REFUSAL)",
        "#   FILE ROWS = `./bin/bend .agents/slop/dw3/scratch*/nn/layers.bend`",
        "# COLLECT THEM ALL WITH `sh .agents/slop/dw3/collect.sh`.",
        "#",
        "# THE PORT'S ANSWER COLUMN HAS THREE VALUES:",
        "#   A SHAPE  -- THE PORT ANSWERED.",
        "#   `NONE`   -- THE PORT REFUSED (`nn_dot` ANSWERED `None`).",
        "#   `<DEAD>` -- THE PORT BUILT A GRAPH WHOSE SHAPE DOES NOT FOLD. NOT A",
        "#               REFUSAL: A WRONG GRAPH HANDED BACK AS IF IT WERE AN ANSWER.",
        "",
    ]

    for key, title, dx, dw in CASES:
        c = cp.get(key)
        if c is None:
            raise SystemExit(f"NO CPYTHON BLOCK FOR {key}")
        lines.append(f"# {key}: {title}   dx={dx} dw={dw}")
        lines.append(f"{key}_dx={dx}")
        lines.append(f"{key}_dw={dw}")
        lines.append(f"{key}_x_shape={c['x_shape']}")
        lines.append(f"{key}_w_shape={c['w_shape']}")
        lines.append(f"{key}_cpython_refused={c['refused']}")
        lines.append(f"{key}_cpython_refusal_mechanism={c['mech']}")
        lines.append(f"{key}_cpython_result={c['result']}")
        lines.append(f"{key}_cpython_x_target={c['x_target']}")
        lines.append(f"{key}_cpython_w_target={c['w_target']}")
        lines.append(f"{key}_cpython_w_permuted={c['w_permuted']}")
        for label, p in (("before", p0), ("s1_guard", p1), ("s2_wshape", p2), ("s3_order", p3), ("after", p4)):
            ws = p.get(f"{key}_wshape", "")
            od = p.get(f"{key}_order", "")
            res = p.get(f"{key}_result", "")
            lines.append(f"{key}_port_{label}_wshape={ws}")
            lines.append(f"{key}_port_{label}_order={od}")
            lines.append(f"{key}_port_{label}_wshape_permuted={apply_order(ws, od)}")
            lines.append(f"{key}_port_{label}_rd={p.get(f'{key}_rd', '')}")
            lines.append(f"{key}_port_{label}_result={res if res else EMPTY}")
        after = p4.get(f"{key}_result", "")
        norm = lambda s: s.replace("(", "").replace(")", "").replace(" ", "").rstrip(",")
        expected = "NONE" if c["refused"] == "yes" else norm(c["result"])
        got = norm(after) if after else EMPTY
        lines.append(f"{key}_port_after_matches_cpython={str(got == expected).lower()}")
        lines.append("")

    lines.append("# THE PORT'S OWN ROWS IN `tinybendygrad/nn/layers.bend` -- S0 / S4.")
    for row in ["dot_2d", "dot_1d", "linear", "linear_nobias", "dbg_dot_sig", "fold_sm",
                "fold_smk", "conv_p1_s1", "conv_seq"]:
        b = f0.get(row, ("", ""))
        a = f4.get(row, ("", ""))
        lines.append(f"row_{row}_before_got={b[0] if b[0] else EMPTY}")
        lines.append(f"row_{row}_after_got={a[0] if a[0] else EMPTY}")
        lines.append(f"row_{row}_want={b[1] if b[1] else EMPTY}")
    lines.append("")

    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"wrote {out_path}")


if __name__ == "__main__":
    main()
