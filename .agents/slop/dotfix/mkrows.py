#!/usr/bin/env python3
"""BUILD `cases.rows` FROM THE CAPTURED INSTRUMENT OUTPUTS. NOTHING IS TYPED IN.

READS, ALL PRODUCED BY `collect.sh`:
  cpython.out    -- `.venv/bin/python cpython_oracle.py`
  port_before.out -- `./bin/bend probe.bend`
  port_after.out  -- `./bin/bend probe_fix.bend`
  rows_before.out -- `./bin/bend scratch/nn/layers.bend`
  rows_after.out  -- `./bin/bend scratchfix/nn/layers.bend`

WRITES: `cases.rows`, ONE `key=value` PER LINE, IN THE ORDER OF THE CASES.
A MISSING OR EMPTY ANSWER IS WRITTEN AS `<EMPTY>`, WHICH IS WHAT THE PORT
ANSWERED -- IT IS NOT A BLANK AND NOT A MISSING ROW.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

CASES = [
    ("A", "x(2,3) . w(3,4)"),
    ("B", "x(2,4,3) . w(3,4)"),
    ("C", "x(8,64,7,7) . w(7,16)"),
    ("D", "x(2,3) . w(3,)"),
    ("E", "x(2,3,4) . w(3,4,5)"),
    ("F", "x(2,3,4) . w(3,4,1)"),
    ("G", "x(3,3,4) . w(3,4,1)"),
]

EMPTY = "<EMPTY>"


def read(path):
    with open(os.path.join(HERE, path), encoding="utf-8") as fh:
        return fh.read()


def cpython_rows(text):
    """`NAME -> {field: value}` FROM THE ORACLE'S OWN OUTPUT."""
    out = {}
    cur = None
    for line in text.splitlines():
        m = re.match(r"^([A-G])$", line.strip())
        if m:
            cur = m.group(1)
            out[cur] = {}
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
        m = re.match(r"^\s+x' target\s+=\s+(\(.*\))\s*$", line)
        if m:
            out[cur]["x_target"] = m.group(1)
            continue
        m = re.match(r"^\s+w' target\s+=\s+(\(.*\)\s+\(before transpose\))\s*$", line)
        if m:
            out[cur]["w_target"] = m.group(1).replace(" (before transpose)", "").strip()
            continue
        m = re.match(r"^\s+x\.dot\(w\)\.shape\s+=\s+(\(.*\))\s*$", line)
        if m:
            out[cur]["result"] = m.group(1)
            continue
        m = re.match(r"^\s+x\.dot\(w\) RAISED\s+=\s+(.*)$", line)
        if m:
            out[cur]["result"] = "RAISED " + m.group(1).strip()
            continue
    return out


def port_rows(text):
    """`A_xshape -> "2,1,3"` FROM THE PROBE'S OWN OUTPUT."""
    out = {}
    for line in text.splitlines():
        m = re.match(r"^([A-G])_(xshape|wshape|order|result)\s*=\s*(.*)$", line.strip())
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


def main():
    out_path = sys.argv[1]
    cp = cpython_rows(read("cpython.out"))
    pb = port_rows(read("port_before.out"))
    pa = port_rows(read("port_after.out"))
    fb = file_rows(read("rows_before.out"))
    fa = file_rows(read("rows_after.out"))

    lines = [
        "# `cases.rows` -- `nn_dot.xshape` (tinybendygrad/nn/layers.bend:291) IS A HEAD DROP.",
        "# EVERY CELL BELOW WAS READ OUT OF AN INSTRUMENT RUN, NOT TYPED IN.",
        "#   CPython         = `.venv/bin/python .agents/slop/dotfix/cpython_oracle.py`",
        "#   PORT BEFORE     = `./bin/bend .agents/slop/dotfix/probe.bend`",
        "#   PORT AFTER      = `./bin/bend .agents/slop/dotfix/probe_fix.bend`",
        "#   FILE ROWS       = `./bin/bend .agents/slop/dotfix/{scratch,scratchfix}/nn/layers.bend`",
        "# COLLECT THEM ALL WITH `sh .agents/slop/dotfix/collect.sh`.",
        "# `<EMPTY>` IS WHAT THE PORT ANSWERED -- AN EMPTY SHAPE READ, NOT A MISSING ROW.",
        "",
    ]

    for key, title in CASES:
        c = cp.get(key)
        if c is None:
            raise SystemExit(f"NO CPYTHON BLOCK FOR {key}")
        lines.append(f"# {key}: {title}")
        lines.append(f"{key}_x_shape={c['x_shape']}")
        lines.append(f"{key}_w_shape={c['w_shape']}")
        lines.append(f"{key}_cpython_x_target={c['x_target']}")
        lines.append(f"{key}_cpython_w_target={c['w_target']}")
        lines.append(f"{key}_cpython_result={c['result']}")
        lines.append(f"{key}_port_before_xshape={pb.get(f'{key}_xshape', EMPTY) or EMPTY}")
        lines.append(f"{key}_port_after_xshape={pa.get(f'{key}_xshape', EMPTY) or EMPTY}")
        lines.append(f"{key}_port_before_wshape={pb.get(f'{key}_wshape', EMPTY) or EMPTY}")
        lines.append(f"{key}_port_after_wshape={pa.get(f'{key}_wshape', EMPTY) or EMPTY}")
        lines.append(f"{key}_port_before_result={pb.get(f'{key}_result', EMPTY) or EMPTY}")
        lines.append(f"{key}_port_after_result={pa.get(f'{key}_result', EMPTY) or EMPTY}")
        agree = pb.get(f"{key}_xshape") != pa.get(f"{key}_xshape")
        lines.append(f"{key}_xshape_moved={str(agree).lower()}")
        lines.append("")

    lines.append("# THE PORT'S OWN ROWS IN `tinybendygrad/nn/layers.bend` -- BEFORE / AFTER.")
    for row in ["dot_2d", "dot_1d", "linear", "linear_nobias", "dbg_dot_sig", "fold_sm"]:
        b = fb.get(row, (EMPTY, EMPTY))
        a = fa.get(row, (EMPTY, EMPTY))
        lines.append(f"row_{row}_before_got={b[0] or EMPTY}")
        lines.append(f"row_{row}_after_got={a[0] or EMPTY}")
        lines.append(f"row_{row}_want={b[1] or EMPTY}")
    lines.append("")

    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
