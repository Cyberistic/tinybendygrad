#!/usr/bin/env python3
"""llm_cli_render-gate.py -- does `llm/cli.bend`'s render agree with upstream's FallbackTemplate.render?

    .venv/bin/python gates/llm_cli_render-gate.py

WHY THIS EXISTS: `render` is the chat template's whole job -- BOS, `<sop>` for glm4, one role/content/
end_turn per message, and the trailing assistant role when `add_generation_prompt` is set -- and it is
the only place those pieces are composed. `llm/cli.bend` ports it as a TWO-PASS map-then-fold (see the
file: a `Maybe`-threaded loop is not expressible here) and this gate is what says the shape change is not
a behaviour change.

THE VOCABULARY IS A STUB, because `SimpleTokenizer.encode` needs a regex engine Bend lacks: `bos` and
`eos` are DECODED strings passed into the port, and the oracle's `decode` answers "BOS"/"EOS" for the same
two ids. That is the same seam `end_turn` takes its eos through.

NEWLINES ARE ESCAPED to '|' ON BOTH SIDES, because every role string ends in newlines and a raw diff
would compare fragments instead of rows.

THE CASES COVER ALL SIX PRESETS and all four content forms, including the TWO THAT RAISE upstream
(a non-text part, and `system` under the tekken preset): upstream raises `RuntimeError`/`ValueError`, the
port answers `None`, and both are printed NONE.
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BEND = ROOT / "bin" / "bend"
DRIVER = ROOT / ".agents" / "slop" / "parity" / "cli_renderdrv.bend"

CONV = [{"role": "user", "content": "hi"}, {"role": "assistant", "content": "yo"}]
CASES = [
  ("llama", "llama3", None, CONV, True),
  ("olmo", "olmo", None, CONV, True),
  ("kimi", "kimi-k2", None, CONV, True),
  ("qwen2", "qwen2", None, CONV, True),
  ("glm4", "glm4", None, CONV, True),
  ("tekken_user", "tekken", None, [{"role": "user", "content": "hi"}], True),
  ("tekken_system", "tekken", None, [{"role": "system", "content": "hi"}], True),
  ("parts", "llama3", None, [{"role": "user", "content": [{"type": "text", "text": "a"},
                                                          {"type": "text", "text": "b"}]}], True),
  ("none", "llama3", None, [{"role": "user", "content": None}], True),
  ("badpart", "llama3", None, [{"role": "user", "content": [{"type": "image"}]}], True),
  ("nogen", "llama3", None, CONV, False),
  ("bos", "llama3", 0, CONV, True),
]


def oracle() -> str:
  sys.path.insert(0, str(ROOT))
  from tinygrad.llm.cli import FallbackTemplate

  class Tok:
    def __init__(self, preset, bos_id):
      self.preset, self.bos_id, self.eos_id = preset, bos_id, -1

    def decode(self, ids):
      if not ids: return ""
      return "BOS" if ids == [0] else "EOS"

  out = []
  for name, preset, bos_id, msgs, gen in CASES:
    t = FallbackTemplate(Tok(preset, bos_id))
    try:
      v = t.render([dict(m) for m in msgs], add_generation_prompt=gen)
    except (RuntimeError, ValueError):
      v = None
    out.append(f"{name}\t{'NONE' if v is None else v.replace(chr(10), '|')}")
  return "\n".join(out) + "\n"


def subject() -> str:
  with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as tf:
    exe = tf.name
  b = subprocess.run([str(BEND), str(DRIVER), "-o", exe], capture_output=True, text=True)
  if b.returncode != 0:
    raise SystemExit(f"the port's render driver did not build: {b.stderr.strip()[:400]}")
  r = subprocess.run([exe], capture_output=True, text=True)
  if r.returncode != 0:
    raise SystemExit(f"the port's render driver did not run: {r.stderr.strip()[:400]}")
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
    print("llm_cli_render: FAIL")
    return 1
  print("llm_cli_render: PASS -- 6 presets x 4 content forms, both raise paths, nogen and a non-empty bos")
  return 0


if __name__ == "__main__":
  sys.exit(main())
