#!/usr/bin/env python3
"""llm_cli_tokenizer-gate.py -- does `llm/cli.bend`'s decode/is_end agree with upstream's, row for row?

    .venv/bin/python gates/llm_cli_tokenizer-gate.py

WHY THIS EXISTS: `ToyTokenizer` here is a STUB vocabulary, and that is deliberate -- `SimpleTokenizer.
__init__` builds a split regex out of `unicodedata.category` ranges, so a real vocabulary cannot be built
in Bend at all (see `cli.bend`'s header). But `decode` and `is_end` do not need that regex: they need the
`tid -> bytes` map and the three end ids. So the gate builds upstream's object with `__new__` and a
hand-set `_tok2bytes`, which is the same seam the port takes its vocabulary through.

WHAT IT PINS: the port re-uses `llm/gguf.bend`'s `utf8.of` rather than re-writing a decoder, so this gate
is what says the two agree -- across a 2-byte code point (U+00E9), a 4-byte one (U+1F642), an empty list,
a mixed list, and an id that is ABSENT from the vocabulary (upstream raises `KeyError`; the port answers
`None`, printed NONE).

THE SEAM, STATED: upstream decodes with `errors='replace'`; `utf8.of` does not emit U+FFFD for an invalid
sequence. The gate therefore uses VALID UTF-8 only, and a vocabulary with invalid bytes is outside the
port's contract -- recorded rather than hidden.
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BEND = ROOT / "bin" / "bend"
DRIVER = ROOT / ".agents" / "slop" / "parity" / "cli_tokdrv.bend"

VOCAB = {0: b"h\xc3\xa9", 1: b"llo", 2: b"\xf0\x9f\x99\x82"}   # "hé", "llo", "🙂"
EOS, EOT, EOM = 0, None, 3
CASES = [("dec/0,1", [0, 1]), ("dec/2", [2]), ("dec/empty", []),
         ("dec/0,2,1", [0, 2, 1]), ("dec/missing", [0, 99])]
ENDS = [0, 3, 1, 4, 99]


def oracle() -> str:
  sys.path.insert(0, str(ROOT))
  from tinygrad.llm.cli import SimpleTokenizer

  t = SimpleTokenizer.__new__(SimpleTokenizer)          # the stub-vocabulary seam
  t._tok2bytes = dict(VOCAB)
  t.eos_id, t.eot_id, t.eom_id = EOS, EOT, EOM
  out = []
  for tag, ids in CASES:
    try:
      out.append(f"{tag}\t{t.decode(ids)}")
    except KeyError:
      out.append(f"{tag}\tNONE")
  for tid in ENDS:
    out.append(f"end/{tid}\t{'True' if t.is_end(tid) else 'False'}")
  return "\n".join(out) + "\n"


def subject() -> str:
  with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as tf:
    exe = tf.name
  b = subprocess.run([str(BEND), str(DRIVER), "-o", exe], capture_output=True, text=True)
  if b.returncode != 0:
    raise SystemExit(f"the port's tokenizer driver did not build: {b.stderr.strip()[:400]}")
  r = subprocess.run([exe], capture_output=True, text=True)
  if r.returncode != 0:
    raise SystemExit(f"the port's tokenizer driver did not run: {r.stderr.strip()[:400]}")
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
    print("llm_cli_tokenizer: FAIL")
    return 1
  print("llm_cli_tokenizer: PASS -- decode and is_end match upstream on 5 id lists and 5 end ids")
  return 0


if __name__ == "__main__":
  sys.exit(main())
