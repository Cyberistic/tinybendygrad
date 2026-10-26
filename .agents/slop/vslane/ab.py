#!/usr/bin/env python3
"""THE A/B ON THE FIXTURE'S OWN LAUNCH: THE PORT'S EXECUTOR vs THE GATE'S OWN ORACLE LANE.

    .venv/bin/python .agents/slop/vslane/ab.py <fixture-name> [<fixture-name> ...]

THE ORACLE IS THE GATE'S OWN: `gates/ops_python_exec-gen.py`'s `py_run` -- upstream's
`tinygrad/runtime/ops_python.py` `PythonProgram.__call__` on the captured `UOp`s, at
`local_size=(1, 1, 1)` (`ops_python_exec-gen.py:416`), which is the WARP THE BEND
EXECUTOR RUNS AT. So this is the SAME comparison the gate makes, on the SAME
fixture, with the SAME rows.

THE PORT'S SIDE IS THE FIXTURE FILE'S OWN PACKET: `gates/ops_python_exec-fixtures.rows`
holds `<name> <gx> <gy> <gz>` and the packet, and the packet is what
`gates/ops_python_exec-gate.py`'s `bd` lane feeds the executor. So this probe runs
THE PORT ON THE PACKET THE GATE RUNS THE PORT ON.

THE HARVEST HAPPENS ONCE. `tinygrad`'s runtime cache means a second pass over the
same seeds does NOT re-render the kernels, so a second harvest yields NOTHING -- a
measurement that silently answers "no fixture" instead of the answer. So the
harvest is ONE pass and every requested fixture is taken from it.

THE FIXTURE FILE'S PACKET TEXT IS STALE AGAINST THE CURRENT tinygrad -- MEASURED:
`tinygrad/uop/ops.py:1225` gives `Ops.PARAM` a SHAPE SRC, so a fresh rendering says
`PARAM f32 k:param:32:g 1` where the fixture file (generated 2026-10-14) says
`PARAM f32 k:param:32:g`, and the fresh rendering of `f32.sqrt.0` has 57 uop lines
where the fixture has 55. THE TWO ARE THE SAME PROGRAM (upstream's `__call__` ignores
a PARAM's src). This probe prints BOTH packets' answers, so the staleness is a
measurement and not a hidden difference.
"""
import importlib.util
import pathlib
import struct
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

import ops_bend as OB  # noqa: E402

sys.modules['tinygrad.runtime.ops_bend'] = OB

# THE GATE's OWN GENERATOR, imported (not reimplemented): its `harvest`, its
# `py_run` (the oracle lane), its `SEEDS`, its `SEED_VALUES`, its `Fixture`.
_spec = importlib.util.spec_from_file_location("opsgen", ROOT / "gates" / "ops_python_exec-gen.py")
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)

OUT = pathlib.Path(__file__).resolve().parent
FIXTURES = ROOT / "gates" / "ops_python_exec-fixtures.rows"


def fixture_file(name):
    """`(argv, body)` for the fixture, read from the tree's own fixture file."""
    recs, cur = [], None
    for ln in FIXTURES.read_text().splitlines():
        if ln.startswith("@ "):
            head = ln.split()[1:]
            cur = [head[0], tuple(int(x) for x in head[1:]), []]
            recs.append(cur)
        elif cur is not None and ln.strip():
            cur[2].append(ln)
    for n, argv, body in recs:
        if n == name:
            return argv, body
    raise KeyError(name)


def elems(bs, dt):
    if dt == gen.dtypes.float:
        n = len(bs) // 4
        return [round(v, 7) for v in struct.unpack(f"<{n}f", bs[:n * 4])]
    if dt == gen.dtypes.bool:
        return list(bs)
    n = len(bs) // 4
    return list(struct.unpack(f"<{n}i", bs[:n * 4]))


def run_port(exe, packet_text, bufs, gsize, tag):
    """the port's executor on ONE packet, in its own directory."""
    d = OUT / "packets" / tag
    d.mkdir(parents=True, exist_ok=True)
    pk = d / "PACKET-0.in"
    with pk.open("w") as fh:
        fh.write(packet_text)
        for b in bufs:
            fh.write(f"{len(b)} {b.hex()}\n")
    r = subprocess.run([str(exe), str(pk), *[str(v) for v in gsize]], capture_output=True, text=True)
    if r.returncode != 0:
        return None, f"rc={r.returncode} {r.stderr.strip()[:200]}"
    po = (d / "PACKET.out").read_text().splitlines()
    return [bytes.fromhex(l.split()[1]) for l in po], ""


def harvest_all(want):
    """ONE pass over the gate's own harvest, keeping only the fixtures asked for."""
    got = {}
    for f in gen.harvest():
        if f.name in want:
            got[f.name] = f
            if len(got) == len(want):
                break
    return got


def main():
    exe = OB.executor()
    names = sys.argv[1:] or ["f32.sqrt.0"]
    print(f"# executor: {exe}")
    got = harvest_all(set(names))
    for name in names:
        dt = {"f32": gen.dtypes.float, "i32": gen.dtypes.int,
              "u32": gen.dtypes.uint, "bool": gen.dtypes.bool}[name.split(".")[0]]
        argv, body = fixture_file(name)
        # the buffer lines are the LAST nbuf lines, and nbuf is the header's third field
        nbuf = int(body[0].split()[2])
        bufs = [bytes.fromhex(l.split()[1]) for l in body[-nbuf:]]
        port, err = run_port(exe, "\n".join(body) + "\n", bufs, argv[:3], f"{name}-fixture")
        print(f"== {name}")
        print(f"#   input      b1: {elems(bufs[1], dt)}")
        print(f"#   PORT (the executor, the FIXTURE's packet): "
              f"{elems(port[0], dt) if port else err}")
        f = got.get(name)
        if f is None:
            print("#   no harvest for this name")
            continue
        _prog, obufs = gen.py_run(f)
        print(f"#   ORACLE (the gate's own oracle lane, upstream's interpreter, warp 1): "
              f"{elems(bytes(obufs[0]), dt)}")
        port2, err2 = run_port(exe, f.packet + "".join(f"{len(b)} {bytes(b).hex()}\n" for b in f.seen()),
                               f.seen(), f.gsize, f"{name}-fresh")
        print(f"#   PORT (the executor, the FRESH packet): "
              f"{elems(port2[0], dt) if port2 else err2}")
        print(f"#   fresh uops={len(f.uops)}  fixture uop lines={len(body) - nbuf - 1}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
