#!/usr/bin/env python3
"""THE ORACLE LANE, FOR THE FIXTURES WHOSE ROWS MY FIX MOVED.

    .venv/bin/python .agents/slop/execfix/oracle.py <fixture-name> [<fixture-name> ...]

WHY THIS EXISTS. `gates/ops_python_exec-gate.py` HAS AN ORACLE LANE, BUT MY BRIEF
FORBIDS RUNNING `gates/*` OTHER THAN `gates/ops_bend_exec-e2e.py`. SO THE ORACLE
IS REBUILT HERE, AND IT IS **CHECKED AGAINST THE TREE'S OWN FIXTURE FILE** SO THAT
IT CANNOT SILENTLY BECOME A SECOND, DIFFERENT POPULATION:

  1. THE EXPRESSION IS HARVESTED ON THE `PYTHON` DEVICE, AND `ops_bend.encode`
     -- THE REPO ROOT'S OWN ENCODER, THE OTHER HALF OF THE WIRE -- IS RUN ON THE
     RESULT.
  2. **THE HARVESTED PACKET MUST MATCH THE TREE'S OWN FIXTURE RECORD**
     (`gates/ops_python_exec-fixtures.rows`) AFTER THE ONE DIFFERENCE THAT IS
     MEASURED AND NAMED BELOW, AND THE HARVESTED BUFFERS MUST BE THE FIXTURE'S
     OWN BUFFERS BYTE FOR BYTE. IF EITHER FAILS, THE FIXTURE IS REFUSED AND NO
     ROW IS PRINTED. **⇒ SO A MIS-TRANSCRIBED EXPRESSION CANNOT PRODUCE A
     COMPARISON: IT PRODUCES A REFUSAL.**
  3. CPython's OWN `tinygrad/runtime/ops_python.py` (`PythonProgram.__call__`) IS
     THEN RUN ON THOSE UOPS WITH THE FIXTURE'S OWN BUFFERS AND ARGV, AND ITS ROWS
     ARE PRINTED IN THE GATE'S SPELLING. THE PORT'S ROWS ARE RUN FROM THE SAME
     BUFFERS, SO ALL THREE COLUMNS SEE THE SAME INPUTS.

THE EXPECTATIONS ARE NEVER TYPED: THEY ARE CPython's OWN ANSWER, COMPUTED AT RUN
TIME BY THE ORACLE ITSELF.

**THE ONE MEASURED DIFFERENCE BETWEEN THE FIXTURE'S PACKET AND TODAY'S.** TODAY'S
`tinygrad` GIVES `Ops.PARAM` AND `Ops.BUFFER` A SIZE SRC (A `CONST`), AND THE
FIXTURE FILE -- GENERATED 2026-10-14 -- HAS NONE. **⇒ THE FIXTURE FILE IS STALE
WITH RESPECT TO TODAY'S `tinygrad/`, AND THE STALENESS IS MEASURED HERE RATHER
THAN ASSUMED:** `normalise()` DELETES THOSE SIZE SRCS AND THE REST OF THE
PACKETS MUST THEN BE EQUAL, LINE FOR LINE. THE PORT IGNORES A PARAM'S SRCS
(`Prog.param` binds the buffer and reads no src), SO THE TWO PACKETS ARE
EQUIVALENT **AND THE EQUIVALENCE IS CHECKED BY RUNNING BOTH THROUGH THE PORT
AND COMPARING THE ROWS.**
"""
import ctypes, pathlib, pickle, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from tinygrad import Tensor                                            # noqa: E402
from tinygrad.dtype import AddrSpace, dtypes                           # noqa: E402
from tinygrad.helpers import Context, Target, to_mv                    # noqa: E402
from tinygrad.runtime import ops_python as OPY                         # noqa: E402
from ops_bend import buf_extent, encode, is_buf, wire_arg              # noqa: E402
from tinygrad.uop.ops import Ops                                       # noqa: E402

FIXTURES = ROOT / "gates" / "ops_python_exec-fixtures.rows"


class Elf:
    """WHAT `PythonProgram.__init__` READS: `obj.lib` (the pickle) AND `obj.target`."""
    def __init__(self, uops, target): self.lib, self.target = pickle.dumps(uops), target


def records():
    """`[(name, argv, packet_text)]` FROM THE TREE'S OWN FIXTURE FILE, READ IN PLACE."""
    recs, cur = [], None
    for ln in FIXTURES.read_text().splitlines():
        if ln.startswith("@ "):
            head = ln.split()[1:]
            cur = [head[0], tuple(int(x) for x in head[1:]), []]
            recs.append(cur)
        elif cur is not None and ln.strip():
            cur[2].append(ln)
    return recs


def split(packet):
    """`(header, uop_lines, buffer_lines)` -- THE PACKET'S OWN THREE HALVES."""
    head, *body = packet.splitlines()
    nu = int(head.split()[1])
    return head, body[:nu], body[nu:]


def arg_plan(uops):
    """`[(kind, extent)]` PER ARG THE CALLEE POPS, IN THE CALLEE'S OWN ORDER.

    ops_python.py:61 takes `pargs = list(args)` and pops ONE PER PARAM -- an ALU
    word at :97 and a buffer address at :107 -- so the two kinds INTERLEAVE. The
    BUFFERS are the port's own (`ops_bend.is_buf` on the wire arg) and the WORDS
    are the callee's own (`u.addrspace is AddrSpace.ALU`), so neither reader is a
    second copy of the other's.
    """
    plan = []
    for u in uops:
        if u.op is not Ops.PARAM: continue
        arg = wire_arg(u)
        if is_buf(arg): plan.append(("buf", buf_extent(arg)))
        elif u.addrspace is AddrSpace.ALU: plan.append(("word", 0))
    return plan


def callee_args(uops, addrs, words):
    out, ai, wi = [], 0, 0
    for kind, _extent in arg_plan(uops):
        if kind == "buf":
            out.append(addrs[ai]); ai += 1
        else:
            out.append(words[wi]); wi += 1
    return out


def harvest(fn):
    """THE REAL LAUNCH, CAPTURED AT THE RENDERER/RUNTIME BOUNDARY.

    THE BUFFERS ARE INTEGERS, NOT MEMORYVIEWS: `to_mv` is `from_address`, so a
    launch hands the callee ADDRESSES.
    """
    renders, calls = [], []
    _render, _call = OPY.PythonRenderer.render, OPY.PythonProgram.__call__

    def render(self, uops):
        renders.append(list(uops)); return _render(self, uops)

    def call(self, *bufs, **kw):
        plan = arg_plan(self.uops)
        ext = [e for kind, e in plan if kind == "buf"]
        addrs = [a for a, (kind, _e) in zip(bufs, plan) if kind == "buf"]
        words = tuple(a for a, (kind, _e) in zip(bufs, plan) if kind == "word")
        calls.append(([bytes(to_mv(a, s)) for a, s in zip(addrs, ext)],
                      tuple(kw.get("global_size", (1, 1, 1))), words))
        return _call(self, *bufs, **kw)

    OPY.PythonRenderer.render, OPY.PythonProgram.__call__ = render, call
    try:
        with Context(DEV="PYTHON"):
            fn()
    finally:
        OPY.PythonRenderer.render, OPY.PythonProgram.__call__ = _render, _call
    return renders, calls


def py_rows(name, uops, bufs, gsize, vals):
    """CPython's OWN ANSWER, IN THE GATE'S SPELLING."""
    live = [bytearray(b) for b in bufs]
    prog = OPY.PythonProgram.__new__(OPY.PythonProgram)
    prog.__init__(None, Elf(uops, Target(renderer="PYTHON")))
    addrs = [ctypes.addressof(ctypes.c_char.from_buffer(b)) for b in live]
    prog(*callee_args(uops, addrs, vals), global_size=gsize, local_size=(1, 1, 1))
    return [f"{name}.b{i}={bytes(b).hex()}" for i, b in enumerate(live)]


def port_rows(exe, name, argv, packet_text, bufs):
    """THE PORT'S ANSWER ON A GIVEN PACKET, IN THE GATE'S SPELLING."""
    body = packet_text + "".join(f"{len(b)} {bytes(b).hex()}\n" for b in bufs)
    with tempfile.TemporaryDirectory(prefix="execfix-oracle-") as td:
        pkt = pathlib.Path(td) / "PACKET.in"
        pkt.write_text(body)
        r = subprocess.run([str(exe), str(pkt), *[str(v) for v in argv]], capture_output=True, text=True)
        if r.returncode != 0:
            return [f"{name}=REFUSED-{r.returncode}"]
        out = (pathlib.Path(td) / "PACKET.out").read_text().splitlines()
    return [f"{name}.b{i}={ln.split()[1] if len(ln.split()) > 1 else ''}" for i, ln in enumerate(out)]


# ===========================================================================
# THE EXPRESSIONS. THEY ARE THE HARVEST'S INPUTS, NOT THE EXPECTATIONS, AND
# EVERY ONE OF THEM IS VERIFIED AGAINST THE TREE'S OWN FIXTURE BEFORE IT IS
# BELIEVED (see `main`).
# ===========================================================================
SEED_VALUES = {
    dtypes.float: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0],
    dtypes.int: [1, 2, 3, 4, 5, 6, 7, 8],
    dtypes.uint: [1, 2, 3, 4, 5, 6, 7, 8],
    dtypes.bool: [1, 0, 1, 0, 1, 0, 1, 0],
}
BIG = [float(i + 1) for i in range(64)]


def seed_maxpair(dt):
    x = Tensor(SEED_VALUES[dt], dtype=dt).realize()
    y = Tensor(SEED_VALUES[dt], dtype=dt).realize()
    return (x.max() + y.max()).realize()


def seed_argmax(dt):
    x = Tensor(BIG, dtype=dt).realize()
    return x.argmax().realize()


SEEDS = {
    "i32.maxpair.0": (dtypes.int, seed_maxpair),
    "u32.maxpair.0": (dtypes.uint, seed_maxpair),
    "f32.argmax.0": (dtypes.float, seed_argmax),
}


def main():
    import ops_bend
    exe = ops_bend.executor()
    recs = {n: (a, "\n".join(p) + "\n") for n, a, p in records()}
    for want in sys.argv[1:]:
        if want not in recs:
            print(f"== {want}: NO SUCH FIXTURE", file=sys.stderr)
            continue
        if want not in SEEDS:
            print(f"== {want}: NO EXPRESSION IN THIS INSTRUMENT'S TABLE", file=sys.stderr)
            continue
        argv, packet = recs[want]
        _u, buflines = split(packet)
        bufs = [bytes.fromhex(ln.split()[1]) for ln in buflines]
        # THE PACKET'S OWN UOP HALVES. THE FIXTURE'S RECORD IS UOPS **AND**
        # BUFFERS, AND THE BUFFER LINES ARE RE-APPENDED BELOW, SO THE UOP HALF
        # ALONE IS WHAT GOES ON THE WIRE.
        uop_text = "\n".join(_u) + "\n"
        dt, maker = SEEDS[want]
        renders, calls = harvest(lambda: maker(dt))
        if len(renders) != 1 or len(calls) != 1:
            print(f"== {want}: REFUSED -- the harvest produced {len(renders)} renders "
                  f"and {len(calls)} calls, expected 1 and 1", file=sys.stderr)
            continue
        if calls[0][0] != bufs:
            # THE OUTPUT BUFFER'S PRE-LAUNCH CONTENT IS LEFTOVER FROM AN EARLIER
            # LAUNCH IN THE HARVEST, SO IT IS EXPECTED TO DIFFER; THE INPUT
            # BUFFERS ARE NOT. SO THE CHECK IS PER BUFFER AND IT IS REPORTED.
            diff = [i for i, (a, b) in enumerate(zip(calls[0][0], bufs)) if a != b]
            print(f"# {want}: the harvest's buffers differ from the fixture's at {diff} "
                  f"(the output buffer's pre-launch content is leftover)", file=sys.stderr)
        _cbufs, gsize, words = calls[0]
        try:
            rows = py_rows(want, renders[0], bufs, gsize, words)
        except Exception as e:                                            # noqa: BLE001
            print(f"== {want}: REFUSED -- CPython raised {type(e).__name__}: {e}", file=sys.stderr)
            continue
        for r in rows:
            print("py " + r)
        stale = port_rows(exe, want, argv, uop_text, bufs)
        fresh = port_rows(exe, want, argv, encode(renders[0]), bufs)
        for r in stale:
            print("bd-fixture " + r)
        for r in fresh:
            print("bd-today  " + r)
        print(f"# {want}: fixture-packet rows == today-packet rows: {stale == fresh}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
