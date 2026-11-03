#!/usr/bin/env python3
"""llm_cli_template-gate.py -- does `llm/cli.bend`'s chat template agree with upstream's, byte for byte?

    .venv/bin/python gates/llm_cli_template-gate.py

WHY THIS EXISTS: `llm/cli.bend` ports `FallbackTemplate.role` and `.end_turn` -- pure string logic keyed
on the tokenizer preset -- and NOTHING checked it. A `--check-only` says the file COMPILES; it says
nothing about whether the six presets produce upstream's six strings. This gate compares all 24 rows
(6 presets x 3 roles, plus `end_turn`) against `tinygrad.llm.cli.FallbackTemplate` itself.

THE SUBJECT is the port's own code, run through `bin/bend`: `parity/clidrv.bend` is the driver and it
prints one row per case. THE ORACLE is upstream's class with a STUB TOKENIZER whose `decode` answers
"EOS" for the eos id -- because the tokenizer is not ported (it needs a regex engine and a Unicode
category table, see cli.bend's header), so the end-of-turn string is passed IN to the port and must be
computed the same way on both sides.

`tekken` + a role it does not have RAISES upstream; the port returns `None` and prints "RAISE", and the
gate asserts BOTH sides say "RAISE" -- a wrong answer here would be a silent empty string, which is why
`role` is a `Maybe` in the port.
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BEND = ROOT / "bin" / "bend"
DRIVER = ROOT / ".agents" / "slop" / "parity" / "clidrv.bend"

PRESETS = [("llama3", "llama"), ("olmo", "olmo"), ("kimi-k2", "kimi"),
           ("qwen2", "qwen2"), ("glm4", "glm4"), ("tekken", "tekken")]
ROLES = ["user", "assistant", "system"]


def oracle() -> str:
  sys.path.insert(0, str(ROOT))
  from tinygrad.llm.cli import FallbackTemplate

  class Tok:
    def __init__(self, preset): self.preset, self.eos_id, self.bos_id = preset, -1, None
    def decode(self, ids): return "EOS" if ids == [-1] else ""

  out = []
  for preset, label in PRESETS:
    t = FallbackTemplate(Tok(preset))
    for r in ROLES:
      try:
        v = t.role(r)
      except ValueError:
        v = "RAISE"
      out.append(f"{label}/{r}\t{v}")
    out.append(f"{label}/end_turn\t{t.end_turn()}")
  return "\n".join(out) + "\n"


def subject() -> str:
  with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as tf:
    exe = tf.name
  b = subprocess.run([str(BEND), str(DRIVER), "-o", exe], capture_output=True, text=True)
  if b.returncode != 0:
    raise SystemExit(f"the port's driver did not build: {b.stderr.strip()[:400]}")
  r = subprocess.run([exe], capture_output=True, text=True)
  if r.returncode != 0:
    raise SystemExit(f"the port's driver did not run: {r.stderr.strip()[:400]}")
  return r.stdout


def main() -> int:
  want, got = oracle(), subject()
  w, g = want.splitlines(), got.splitlines()
  bad = [f"  row {i}: port={g[i]!r} upstream={w[i]!r}"
         for i in range(min(len(w), len(g))) if w[i] != g[i]]
  if len(w) != len(g):
    bad.append(f"  row count: port={len(g)} upstream={len(w)}")
  print(f"rows  {len(g)} port / {len(w)} upstream, {len(bad)} differ")
  if bad:
    print("\n".join(bad[:8]))
    print("llm_cli_template: FAIL")
    return 1
  print("llm_cli_template: PASS -- every preset x role and end_turn is byte-identical to upstream")
  return 0


if __name__ == "__main__":
  sys.exit(main())
