#!/usr/bin/env python3
"""ops_python.py oracle + the TWO-LANE harness for `tinybendygrad/runtime/ops_python.bend`.

WHAT IS BEING ORACLE-GATED. `tinygrad/runtime/ops_python.py` is CPython's uop
emulator: it base64-pickles a uop list and INTERPRETS it, one `while i <
len(self.uops)` at a time. The port `tinybendygrad/runtime/ops_python.bend` is the
same `PythonProgram.__call__` loop, reading a text wire. This file

  1. asks tinygrad for the real uop stream of a set of expressions (via
     `Device['BEND']`, whose `BendRenderer` forks `PythonRenderer`),
  2. captures the FULL packet `BendProgram.__call__` writes -- uop lines AND the
     buffer lines. `.agents/slop/packet-<case>.txt` does NOT carry the buffer
     lines, so those files are not enough to run the executor by hand,
  3. runs the executor's NATIVE binary on it, and the INTERPRETER on it, and
  4. runs CPython's own `PythonProgram` (i.e. `Device['PYTHON']`) on the SAME
     tensors,
then prints `name=value` rows. No expectation in this project is re-transcribed:
every `py_*` row is what CPython answered.

THE RENDERER/COMPILER/DEVICE half of ops_python.py is gated separately by
`.agents/slop/ops-python-render-oracle.py`, which calls CPython's `PythonRenderer`
directly.

    .venv/bin/python .agents/slop/ops-python-probe.py            # both lanes, per case
    .venv/bin/python .agents/slop/ops-python-probe.py --quiet    # rows only

THREE TRAPS MEASURED WHILE WRITING THIS, each of which silently fakes a pass:

  * `Tensor.arange(16, dtype=float32).realize()` REALIZES TO **CPU**, not to the
    Context's device. With arange-built inputs, `xs@ys`, `xs.permute((1,0))`,
    `xs.max(axis=0)`, `(xs*ys).sum(axis=0)` and `(xs+ys).reshape(16)` are all
    dispatched to `CPUProgram` and `BendRenderer.render` is called ZERO times --
    so the BEND executor is not exercised at all and the answer is trivially
    right. Measured: `Tensor([...]).realize()` DOES land on BEND; arange does
    not. Every input here is an explicit float list for that reason.
    This is also why `.agents/slop/bend_e2e.py`'s `dot` case is VACUOUS: its
    `xs`/`ys` come from arange, so `packet-dot.txt` is not a BEND kernel at all.
  * The kernel cache is keyed by the AST and survives the process, so on the
    SECOND run of any of these scripts the kernels are cache HITS, no program is
    launched, and no packet is captured -- with the answers still correct. Hence
    `CACHELEVEL=0` on both Contexts.
  * Input tensors built OUTSIDE `Context(DEV='BEND')` realize on the DEFAULT
    device, which is METAL on this box, and the first `.realize()` dies with
    `RuntimeError: Attempting to relocate against an undefined symbol
    sel_registerName` from `tinygrad/runtime/support/elf.py`. It looks like a
    BEND failure and is not.
"""
import pathlib, struct, subprocess, sys

OUT = pathlib.Path(__file__).parent
REPO = OUT.parent.parent
SRC = REPO/"tinybendygrad"/"runtime"/"ops_python.bend"
BEND = REPO/"bin"/"bend"


def _cases(T, dtypes):
  # ORDER SENSITIVE BY CONSTRUCTION, AND NO OUTPUT IS ALL-EQUAL.
  #   * every operand is DISTINCT, so a port that reversed a source list, or
  #     swapped the two src slots of a binary op, answers something else. A
  #     symmetric fixture (x+x) cannot see that at all.
  #   * no case may print one repeated value. `b / a` over a=[1,2,3,4],
  #     b=[10,20,30,40] is [10,10,10,10] and `a > b` is [F,F,F,F]; both are
  #     order-INVISIBLE, which is the trap the brief names. `div4` is `i / k`
  #     and `cmp` is `a > (b - a)` for exactly that reason.
  a = T([1.0, 2.0, 3.0, 4.0]).realize()
  b = T([10.0, 20.0, 30.0, 40.0]).realize()
  i = T([1, 2, 3, 4], dtype=dtypes.int32).realize()
  j = T([7, 8, 9, 10], dtype=dtypes.uint32).realize()
  k = T([3, 1, 4, 1], dtype=dtypes.int32).realize()
  # 4x4 from EXPLICIT LISTS, not arange -- see the module docstring.
  xs = T([float(v + 1) for v in range(16)]).realize().reshape(4, 4)
  ys = T([float(2 * v + 1) for v in range(16)]).realize().reshape(4, 4)
  return [('add4', lambda: a + b), ('sub4', lambda: b - a), ('mul4', lambda: a * b),
          ('div4', lambda: i / k),
          ('sum4', lambda: a[:4].sum(axis=0)),
          ('addi32', lambda: i + k), ('addu32', lambda: j + 1),
          ('subi32', lambda: i - k), ('muli32', lambda: i * k),
          ('shli32', lambda: i << k), ('shri32', lambda: i >> k),
          ('andi32', lambda: i & k), ('ori32', lambda: i | k), ('xori32', lambda: i ^ k),
          ('cast', lambda: (i + k).cast(dtypes.float32)),
          ('cmp', lambda: a > (b - a)), ('cmp3', lambda: (a < b).where(a * b, b - a)),
          ('dot', lambda: xs @ ys),
          ('mulacc', lambda: (xs * ys).sum(axis=0)),
          ('maxred', lambda: xs.max(axis=0)),
          ('permute', lambda: xs.permute((1, 0))),
          ('reshape', lambda: (xs + ys).reshape(16)),
          ('flip', lambda: (a * b).flip(0)),
          ('shrink', lambda: (a * b)[1:3]),
          ('log', lambda: (a * b).log()), ('sqrt', lambda: (a * b).sqrt()),
          ('where', lambda: (a > b).where(a * b, b - a)),
          ]


def cases():
  from tinygrad import Tensor, Context
  from tinygrad.dtype import dtypes
  with Context(DEV='BEND', CACHELEVEL=0):
    return _cases(Tensor, dtypes)


CAP = []


def capture():
  """Capture the FULL packet WITHOUT patching the `subprocess` MODULE, which
  tinygrad's own device compilers use. `BendProgram.__call__` builds PACKET.in from
  `self.src` plus one hex line per input buffer, so wrapping the call reproduces
  the file byte for byte."""
  import tinygrad.runtime.ops_bend as OB
  from tinygrad.helpers import to_mv
  real = OB.BendProgram.__call__

  def spy(self, *bufs, **kw):
    views = [to_mv(b, nb) for b, nb in zip(bufs, self.in_bufs)]
    CAP.append((self.src + "".join(f"{len(v)} {bytes(v).hex()}\n" for v in views),
                [str(x) for x in (*kw.get("global_size", (1, 1, 1)), *kw.get("vals", ()))]))
    return real(self, *bufs, **kw)
  OB.BendProgram.__call__ = spy
  return real


def ref(thunk):
  """CPython's own answer, from the PYTHON device -- the emulator this file ports."""
  from tinygrad import Context
  with Context(DEV='PYTHON', CACHELEVEL=0):
    return thunk().tolist()


def run_packet(exe, pkt, argv, workdir):
  workdir.mkdir(parents=True, exist_ok=True)
  (workdir/"PACKET.in").write_text(pkt)
  cmd = [str(exe), str(workdir/"PACKET.in"), *argv] if exe is not None else \
        [str(BEND), str(SRC), str(workdir/"PACKET.in"), *argv]
  r = subprocess.run(cmd, capture_output=True, text=True)
  out = workdir/"PACKET.out"
  return r, (out.read_text() if out.exists() else None)


def words(out):
  """PACKET.out as lists of 4-byte words, little endian, both as u32 and as f32.

  The wire is hex bytes; the ONLY thing a packet carries is 4-byte lanes, so this
  is a total decode and not a guess about a dtype. A CPU-side comparison decodes
  CPython's own output buffer the same way, which is why no dtype is guessed here
  either."""
  if out is None: return None
  rows = []
  for ln in out.splitlines():
    _, hx = ln.split()
    b = bytes.fromhex(hx)
    us = [struct.unpack_from('<I', b, o)[0] for o in range(0, len(b) - 3, 4)]
    fs = [struct.unpack_from('<f', b, o)[0] for o in range(0, len(b) - 3, 4)]
    rows.append((us, fs))
  return rows


def main():
  quiet = '--quiet' in sys.argv
  capture()
  import tinygrad.runtime.ops_bend as OB
  exe = OB.executor()
  from tinygrad import Context
  nd = OUT/"ops-python-packets"
  nd.mkdir(exist_ok=True)
  if not quiet: print('# native-exe', exe); print('# bend      ', BEND, SRC)
  for name, thunk in cases():
    CAP.clear()
    with Context(DEV='BEND', CACHELEVEL=0):
      try:
        bend_ans = thunk().tolist()
      except Exception as e:
        print(f'render_{name}=REFUSED {type(e).__name__}: {e}'); continue
    if not CAP:
      print(f'render_{name}=0')
      print(f'py_{name}={bend_ans!r}')
      print(f'note_{name}=no BEND kernel: this expression ran on the HOST, so it gates nothing')
      continue
    pkt, argv = CAP[-1]
    (nd/f'packet-{name}.txt').write_text(pkt)
    rn, on = run_packet(exe, pkt, argv, nd/f'nat-{name}')
    ri, oi = run_packet(None, pkt, argv, nd/f'int-{name}')
    try: want = ref(thunk)
    except Exception as e: want = f'ERR {type(e).__name__}: {e}'
    print(f'render_{name}={len(pkt.splitlines()) - 1 - int(pkt.split()[1])}')
    print(f'natrc_{name}={rn.returncode} intrc_{name}={ri.returncode}')
    print(f'lanes_{name}={on == oi}')
    print(f'nat_{name}={words(on)!r}')
    print(f'int_{name}={words(oi)!r}')
    print(f'py_{name}={want!r}')
    if rn.returncode != 0: print(f'natmsg_{name}={(rn.stderr or rn.stdout).strip()[:200]!r}')
    if ri.returncode != 0: print(f'intmsg_{name}={(ri.stderr or ri.stdout).strip()[:200]!r}')


if __name__ == '__main__':
  sys.exit(main())