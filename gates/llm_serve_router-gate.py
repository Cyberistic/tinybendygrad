#!/usr/bin/env python3
"""llm_serve_router-gate.py -- does `llm/serve.bend`'s StreamRouter agree with upstream's, delta for delta?

    .venv/bin/python gates/llm_serve_router-gate.py

WHY THIS EXISTS: `StreamRouter` is the streaming state machine in `tinygrad/llm/serve.py:43-70` -- it
splits streamed text on `<think>` / `</think>` / `<tool_call>` and routes each piece to
`reasoning_content` or `content`. `llm/serve.bend` ports it as a PURE function (the new `Router` and the
deltas are returned instead of mutated and yielded, because Bend has no mutable cell), and NOTHING checked
that the representation change preserved the behaviour.

THE SUBJECT is the port, run through `bin/bend`: `parity/serve_routerdrv.bend` replays six piece
sequences and prints every delta plus the final `(mode, buf)`. THE ORACLE is upstream's `StreamRouter`
over the SAME sequences, printed in the same format.

THE SIX SEQUENCES are chosen to reach each branch: a stream that opens with a SPLIT `<think>` tag, plain
content, a `<tool_call>`, `reasoning=True` with no think block (so the mode starts decided), a PARTIAL
tag at the end (which must be HELD, not emitted), and two empty pieces. A router that emitted the held
back suffix, or forgot to switch from reasoning to content, would differ on one of them.

THE INPUTS CONTAIN NO NEWLINES, so a line-based diff IS a byte comparison of the deltas.
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BEND = ROOT / "bin" / "bend"
DRIVER = ROOT / ".agents" / "slop" / "parity" / "serve_routerdrv.bend"

SEQS = [
  ("reason", True, ["<thin", "k>rea", "soning</thi", "nk>hel", "lo"]),
  ("plain", False, ["he", "llo"]),
  ("tool", False, ['hi<tool_call>{"a":1}']),
  ("nothnk", True, ["no think here"]),
  ("hold", False, ["x<tool_c"]),
  ("empty", True, ["", ""]),
]
FIELD = {"reasoning_content": "R", "content": "C"}


def oracle() -> str:
  sys.path.insert(0, str(ROOT))
  from tinygrad.llm.serve import StreamRouter

  out = []
  for name, reasoning, pieces in SEQS:
    r = StreamRouter(reasoning)
    for i, p in enumerate(pieces):
      for field, text in r.route(p, i == len(pieces) - 1):
        out.append(f"{name}/{FIELD[field]}\t{text}")
    out.append(f"{name}/final\t{r.mode}\t{r.buf}")
  return "\n".join(out) + "\n"


def subject() -> str:
  with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as tf:
    exe = tf.name
  b = subprocess.run([str(BEND), str(DRIVER), "-o", exe], capture_output=True, text=True)
  if b.returncode != 0:
    raise SystemExit(f"the port's router driver did not build: {b.stderr.strip()[:400]}")
  r = subprocess.run([exe], capture_output=True, text=True)
  if r.returncode != 0:
    raise SystemExit(f"the port's router driver did not run: {r.stderr.strip()[:400]}")
  return r.stdout


def main() -> int:
  want, got = oracle(), subject()
  w, g = want.splitlines(), got.splitlines()
  bad = [f"  row {i}: port={g[i]!r} upstream={w[i]!r}" for i in range(min(len(w), len(g))) if w[i] != g[i]]
  if len(w) != len(g):
    bad.append(f"  row count: port={len(g)} upstream={len(w)}")
  print(f"rows  {len(g)} port / {len(w)} upstream, {len(bad)} differ")
  if bad:
    print("\n".join(bad[:8]))
    print("llm_serve_router: FAIL")
    return 1
  print("llm_serve_router: PASS -- every delta and the final (mode, buf) match upstream on 6 sequences")
  return 0


if __name__ == "__main__":
  sys.exit(main())
