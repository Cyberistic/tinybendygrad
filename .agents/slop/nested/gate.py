#!/usr/bin/env python3
"""THE NESTED-RANGE GATE.  One lane, and nothing of the port's answer is trusted.

WHAT IT DOES, per case, all from files on disk:

  1. reads `packet-<case>.txt` -- the wire the port's OWN `encode()` wrote, uop lines
     AND buffer lines -- and `argv-<case>.txt`, the launch grid;
  2. MEASURES loop depth from the wire TEXT alone (`RANGE` lines, `END`'s second src),
     so the depth column cannot be inherited from an assumption;
  3. finds the OUTPUT buffer by walking STORE -> SHRINK -> PARAM, i.e. by the wire;
  4. runs the COMPILED executor -- `tinybendygrad/runtime/ops_python.bend -o exe` -- as
     a separate process.  There is no Python interpreter of the uops in this path;
  5. decodes PACKET.out and compares the WHOLE output buffer against
     `oracle-<case>.json`, which was written by CALLING CPython's `Device['PYTHON']`
     on the same expression.  Not a prefix: every word is compared and the differing
     indices are printed.

    .venv/bin/python .agents/slop/nested/gate.py <executor> [case ...]

EXIT: 0 iff every case matches on every word AND at least one depth>=2 case ran.
"""
import json, pathlib, struct, subprocess, sys, tempfile, os

HERE = pathlib.Path(__file__).parent


def flat(x, out=None):
  """`Device['PYTHON'].data().tolist()` is NESTED for an N-D tensor and the wire's
  output buffer is FLAT, so the oracle is flattened here.  Every leaf must be a real
  number: a ragged or non-numeric oracle is a REFUSAL, not a comparison."""
  out = [] if out is None else out
  if isinstance(x, list):
    for y in x: flat(y, out)
  elif isinstance(x, (int, float)):
    out.append(float(x))
  else:
    raise SystemExit(f"*** oracle holds a non-number {x!r} -- not a verdict ***")
  return out


def words(line):
  hx = line.split()[1]
  b = bytes.fromhex(hx)
  return [struct.unpack_from('<f', b, o)[0] for o in range(0, len(b) - 3, 4)]


def wire(path):
  """(uops, bufs) from the packet text.  `uops` is a list of dicts; every field this
  gate uses is READ, never assumed."""
  lines = path.read_text().splitlines()
  head = lines[0].split()
  assert head[0] == "bendexec1", head
  nu, nbuf = int(head[1]), int(head[2])
  us, bufs = [], []
  for ln in lines[1:]:
    if ": " in ln.split()[0] + " ":
      idx, rest = ln.split(": ", 1)
      f = rest.split()
      us.append({"i": int(idx), "op": f[0], "dt": f[1], "arg": f[2],
                 "srcs": [int(x) - 1 for x in f[3:]]})
    else:
      bufs.append(ln)
  assert len(us) == nu, (len(us), nu)
  assert len(bufs) == nbuf, (len(bufs), nbuf)
  return us, bufs


def depth_of(us):
  """Loop DEPTH, measured from the text.  A RANGE is inside another when an END
  names it while it sits after the enclosing RANGE and before the enclosing END."""
  ends = [(i, u["srcs"][1]) for i, u in enumerate(us) if u["op"] in ("END", "BACKEDGE")
          and len(u["srcs"]) > 1]
  out = {}
  for i, u in enumerate(us):
    if u["op"] != "RANGE": continue
    d = 1
    for _, st in ends:
      if st != i and st < i: d += 1
    out[i] = d
  return out


def out_index(us):
  """Which packet buffer the kernel WRITES, by walking STORE -> src0 -> ... -> PARAM
  and counting the addrspace-g PARAMs in uop order (the port pops pbufs in that order,
  ops_bend.py's WRITEBACK comment)."""
  def buf_of(i, seen=()):
    if i in seen: return None
    seen = seen + (i,)
    u = us[i]
    if u["op"] == "PARAM" and u["arg"].endswith(":g"): return 0
    if u["op"] == "PARAM": return None
    if u["srcs"]:
      r = buf_of(u["srcs"][0], seen)
      if r is not None: return r
    return None
  g = [i for i, u in enumerate(us) if u["op"] == "PARAM" and u["arg"].endswith(":g")]
  for i, u in enumerate(us):
    if u["op"] != "STORE": continue
    seen, cur = set(), u["srcs"][0]
    while cur not in seen:
      seen.add(cur)
      if us[cur]["op"] == "PARAM" and us[cur]["arg"].endswith(":g"):
        return g.index(cur)
      cur = us[cur]["srcs"][0] if us[cur]["srcs"] else None
      if cur is None: break
  return -1


def main():
  exe = pathlib.Path(sys.argv[1]).resolve()
  want = sys.argv[2:] or sorted(p.stem[7:] for p in HERE.glob("packet-*.txt"))
  tmp = pathlib.Path(tempfile.mkdtemp(prefix="nested-gate-"))
  rows, deep, bad = [], 0, 0
  print(f"executor {exe}")
  print(f"{'case':10s} {'depth':>5s} {'RANGE':>5s} {'grid':>8s} {'words':>5s} {'match':>5s}  detail")
  for nm in want:
    pk, av, orf = HERE/f"packet-{nm}.txt", HERE/f"argv-{nm}.txt", HERE/f"oracle-{nm}.json"
    if not (pk.exists() and av.exists() and orf.exists()):
      print(f"{nm:10s}  *** NO PACKET/ARGV/ORACLE -- not run, and not a verdict ***"); bad += 1; continue
    us, _ = wire(pk)
    d = depth_of(us)
    md = max(d.values(), default=0)
    nr = len(d)
    if md >= 2: deep += 1
    oi = out_index(us)
    grid = av.read_text().split()
    (tmp/"PACKET.in").write_text(pk.read_text())
    (tmp/"PACKET.out").unlink(missing_ok=True)
    r = subprocess.run([str(exe), str(tmp/"PACKET.in"), *grid], capture_output=True, text=True)
    outp = tmp/"PACKET.out"
    if not outp.exists():
      print(f"{nm:10s} depth={md} *** NO PACKET.out, rc={r.returncode}: "
            f"{(r.stderr or r.stdout).strip()[:90]} *** -- the lane FELL OVER, not a verdict ***")
      bad += 1; continue
    got = words(outp.read_text().splitlines()[oi])
    want_w = flat(json.loads(orf.read_text())["out"])
    n = min(len(got), len(want_w))
    bad_i = [k for k in range(n) if got[k] != want_w[k]]
    lent = len(got) != len(want_w)
    ok = (not bad_i) and (not lent)
    if not ok: bad += 1
    sh = "%.4g"
    det = ("all words bit-identical" if ok else
           (f"LENGTH {len(got)} vs {len(want_w)}; " if lent else "") +
           f"{len(bad_i)} of {n} differ, first 5 idx {bad_i[:5]}; "
           + (f"got {[sh % got[k] for k in bad_i[:3]]} want {[sh % want_w[k] for k in bad_i[:3]]}"
              if bad_i else ""))
    print(f"{nm:10s} {md:5d} {nr:5d} {'x'.join(grid[:3]):>8s} {n:5d} {str(ok):>5s}  {det}")
    rows.append((nm, md, nr, n, ok))
  print()
  print(f"cases={len(rows)}  max-depth>=2 cases={deep}  mismatching={bad}")
  print("NOTE: a run with deep=0 proves nothing about nesting -- that is the "
        "single-loop-green trap. This gate refuses to claim it.")
  if deep == 0:
    print("*** REFUSED, NOT A VERDICT: no depth>=2 case ran ***"); return 3
  return 1 if bad else 0

if __name__ == "__main__":
  sys.exit(main())
