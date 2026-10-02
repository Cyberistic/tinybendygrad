#!/usr/bin/env python
"""Mutation runner for the ports in this unit.

  usage: python .agents/slop/mutate.py <file.bend> <muts.txt> <baseline.txt> [label]

muts.txt, one stanza per mutation --

    --- <name>
    LINE <exact substring of the target line>
    NEW  <the WHOLE replacement line>

Line-oriented on purpose. A substring-pair format cannot express "change the 2 on the
line after `def tgt_kinds()`", and a mutation that silently mutates nothing is the worst
kind: the harness therefore REQUIRES exactly one line to match and reports a stale
stanza as a failure rather than as "moved 0 rows".

Each mutation is written BESIDE the port (a copy outside the tree cannot resolve a
relative import -- agent-core), run through ./bin/bend, and compared to the baseline by
WHOLE `name=value` LINE. A name-comparing harness reported 0 moved rows for all 30
mutations in one unit and 0 for all 68 in another.

THREE THINGS THIS REFUSES TO DO, because all three have happened:
  * a 0-row run is reported as INCONCLUSIVE and never as "moved nothing" -- bend 2.0.34's
    stack overflow prints nothing roughly one run in twenty, and 0 rows is
    indistinguishable from "not started";
  * the port is re-run before each mutation and the run aborted if the BASELINE moved,
    because another agent editing a dependency makes every row appear to move;
  * the port file itself is never written to, and is re-read afterwards and compared.
"""
import pathlib
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
BEND = REPO / "bin" / "bend"


TRANSIENT = ("machine stack overflow", "SOME PROOFS FAIL", "Error:")


def run_bend(path):
  """(rows, first_output_line), retried through every transient failure shape.

  `rows` is the parsed `name=value` set. It is EMPTY both when the compiler failed and
  when 2.0.34's stack overflow printed nothing, and those two must never be read as a
  verdict: the first run of this harness reported "38 rows moved" for five mutations that
  were merely MALFORMED, because a compile error parses to zero rows and an empty row set
  differs from every baseline row.

  The retry is on a MARKER as well as on emptiness. A concurrent agent mid-edit in a
  dependency makes a file this unit does not own fail to compile or trip `dtype.bend`'s
  14 permanently-red laws for a moment -- measured here, one mutation of twenty came back
  `SOME PROOFS FAIL` and produced correct rows on all three manual re-runs -- and reading
  that as INCONCLUSIVE for the mutant rather than as a transient is the difference between
  a mutation table and a table of noise.
  """
  first = "<no output>"
  for _ in range(6):
    p = subprocess.run([str(BEND), str(path)], capture_output=True, text=True,
                       cwd=str(REPO), timeout=900)
    out = (p.stdout + p.stderr).strip()
    if out:
      got = rows(out)
      first = out.splitlines()[0]
      if got and not any(m in out for m in TRANSIENT):
        return got, first
  return {}, first


def rows(text):
  out = {}
  for line in text.splitlines():
    if "=" in line and not line.startswith("#"):
      k, _, v = line.partition("=")
      out[k] = v
  return out


def parse_muts(path):
  muts, cur = [], None
  for n, line in enumerate(pathlib.Path(path).read_text().splitlines(), 1):
    if line.startswith("--- "):
      cur = {"name": line[4:].strip(), "line": None, "new": None}
      muts.append(cur)
    elif line.strip() and not line.startswith(("#", "LINE ", "NEW  ")):
      raise ValueError(f"line {n} is neither a comment, a LINE, nor a NEW: {line!r}. "
                       "`---` alone marks a stanza, so using it for a continuation line "
                       "silently starts a NEW stanza and drops the real one.")
    elif line.startswith("LINE "):
      cur["line"] = line[5:]
    elif line.startswith("NEW  "):
      # ACCUMULATE, not overwrite. Two NEW lines make a stanza that INSERTS a line; with
      # overwrite semantics the second replaced the first, so "re-insert the deleted rule"
      # silently SWAPPED one rule for another and moved nothing -- a mutation that
      # reported 0 moved rows for a reason that had nothing to do with the gate.
      cur["new"] = (cur["new"] + "\n" + line[5:]) if cur["new"] else line[5:]
  # A stanza with no LINE or no NEW is a typo, and dropping it is how "re-insert the
  # deleted rule" once reported 0 moved rows because its LINE had been swallowed by the
  # stanza above it. Loud, not silent.
  for m in muts:
    if not m["line"] or not m["new"]:
      raise ValueError(f"stanza {m['name']!r} is missing a LINE or a NEW")
  return muts


def apply_mut(lines, m):
  """The one line whose text contains `m['line']`, replaced whole by `m['new']`.

  Exactly one line must match, so a stanza that has gone stale is a loud failure and not
  a silent no-op. The matched line's LEADING WHITESPACE is prepended to the replacement,
  so a stanza never has to re-type the indentation: getting that wrong is not a failed
  mutation but a file that will not parse, and one such stanza here reported itself as
  "INCONCLUSIVE -- no rows" because a compile error and a stack overflow both look like
  zero rows.
  """
  hits = [i for i, ln in enumerate(lines) if m["line"] in ln]
  if len(hits) != 1:
    raise ValueError(f"{m['line']!r} matched {len(hits)} lines, want 1")
  i = hits[0]
  indent = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
  # A multi-line replacement gets the SAME indent on every line, so a stanza that inserts
  # a line never has to spell the indentation of a line that does not exist yet.
  body = [(indent + ln if ln else "") for ln in m["new"].split("\n")]
  lines[i:i + 1] = body
  return lines


def main():
  target, muts_path, baseline_path = sys.argv[1], sys.argv[2], sys.argv[3]
  label = sys.argv[4] if len(sys.argv) > 4 else pathlib.Path(target).name
  target = REPO / target
  base_text = (REPO / baseline_path).read_text()
  base = rows(base_text)
  if not base:
    print(f"{label}: BASELINE IS EMPTY -- aborting", file=sys.stderr)
    return 2

  check, first = run_bend(target)
  if not check:
    print(f"{label}: UNMUTATED RUN EMITTED ZERO ROWS ({first}) -- aborting",
          file=sys.stderr)
    return 2
  if check != base:
    print(f"{label}: PORT HAS MOVED SINCE THE BASELINE -- aborting", file=sys.stderr)
    for k in sorted(set(base) | set(check)):
      if base.get(k) != check.get(k):
        print(f"  {k}: baseline={base.get(k)} now={check.get(k)}")
    return 2

  original = target.read_text()
  muts = parse_muts(REPO / muts_path)
  failures = 0
  for m in muts:
    try:
      lines = apply_mut(original.splitlines(), m)
    except ValueError as e:
      print(f"  {m['name']}: STALE -- {e}")
      failures += 1
      continue
    beside = target.with_suffix(".mutant.bend")
    beside.write_text("\n".join(lines) + "\n")
    try:
      got, first = run_bend(beside)
    finally:
      beside.unlink(missing_ok=True)
    if not got:
      print(f"  {m['name']}: NO ROWS after 6 attempts -- the stanza is probably "
            f"malformed, not transient. compiler said: {first}")
      failures += 1
      continue
    moved = sorted(k for k in set(base) | set(got) if base.get(k) != got.get(k))
    if not moved:
      print(f"  {m['name']}: 0 MOVED -- BLIND SPOT")
      failures += 1
    else:
      print(f"  {m['name']}: {len(moved)} moved  {moved}")

  if target.read_text() != original:
    print(f"{label}: PORT WAS MODIFIED -- restore it", file=sys.stderr)
    return 2
  print(f"{label}: {len(muts)} mutations, {failures} problems")
  return 1 if failures else 0


if __name__ == "__main__":
  sys.exit(main())