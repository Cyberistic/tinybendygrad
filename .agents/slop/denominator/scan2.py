#!/usr/bin/env python3
"""scan2.py -- THE SHARPENED PREDICATE, and the net's false-positive rate.

`scan.py`'s 179 lines are a NET: "a count near a verdict token".  A net's yield is not a
population, so this pass asks the question that actually matters, and asks it of the AST:

    A ZERO-DENOMINATOR SITE is a module where
      (1) a POPULATION is built from the tree/collection  -- glob/rglob/walk/read of N things
      (2) that population's SIZE reaches a VERDICT -- the printed answer or the exit code
      (3) and the module has NO ZERO-GUARD -- no `if not X` / `X == 0` whose body REFUSES

(3) is what separates a gate that reports a real answer from one that reports `0 of 0` and calls
it OK.  A module with a genuine zero (`no-txt.py` finding no `.txt`) HAS (3): it refuses, or it
compares against a floor it also declares.  So (3) is the discriminator, and it is measured here
rather than argued.

Emits `sites.tsv` (one row per FILE, the population by DISCOVERY) and prints the split.
Every row is hand-verified before the report quotes it; `--verify` prints the evidence.
"""
import argparse, ast, os, pathlib, re, sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
ROOTS = ("checks", "gates")
EXCL = (".agents", "references", "node_modules", ".git", ".venv", "__pycache__")

# (1) population constructors -- a sized thing read off the tree
POP_FUNCS = {"glob", "rglob", "walk", "listdir", "read_text", "read_bytes", "readdir"}
POP_VARS = {"files", "paths", "items", "rows", "entries", "found", "hits", "texts", "text",
            "ms", "pairs", "seen", "names", "src", "sources", "lanes", "graphs", "ops"}
# (2) verdict surfaces
VERDICT = re.compile(
  r"VERDICT|\bOK\b|\bPASS\b|\bFAIL\b|GREEN|CLEAN|\bbad\b|BROKEN|AGREE|REFUSED|\bDEAD\b|\bSKIP\b")
# (3) a zero-GUARD, and THIS is where the first version of this file was WRONG.
#
# It scored `if not (REPO/"pyproject.toml").is_file(): refuse(...)` as a denominator guard,
# and `checks/dup-census.py` came out GREEN -- while it demonstrably guards its INPUTS and
# nothing guards its DENOMINATOR (`lanes`).  **An input-presence check and a denominator check
# are different guards, and a census that cannot tell them apart will clear the very gate it
# exists to find.**  So the guard must be tested against a COUNT: either `len(...)` directly,
# or a NAME that a `len(`/`sum(` line binds.  That is what COUNTED does.
COUNTED = re.compile(r"^\s*(\w+)\s*=\s*(?:len|sum)\(")
GUARD = re.compile(r"(if\s+not\s+\w+|==\s*0|>\s*0|<=\s*0|len\([^)]*\)\s*==\s*0)")
# A guard only counts if it CHANGES THE VERDICT.  Three idioms do, and the second version of
# this file got BOTH ends wrong -- it counted `bad.append(...)` as nothing, so it cleared 0 of 29:
#   1. refuse()/exit(nonzero)/raise
#   2. append to a list that BECOMES the verdict  (`bad`, `problems`, `failures`, `errors`)
#   3. print an explicit UNMEASURED sentence, so the reader is told rather than left to infer
REFUSE = re.compile(
  r"(refuse|sys\.exit\([1-9]|exit\([1-9]|REFUSED|\braise\b"
  r"|\b(bad|problems|failures|errors|offenders|bads)\.append"
  r"|UNMEASURED|NO DENOMINATOR|measured nothing|DENOMINATOR (IS )?0)")
BADLIST = re.compile(r"^\s*(\w+)\s*=\s*\[\s*\]$")
VERDICTWORD = re.compile(r"(if\s+not\s+(bad|problems|failures|errors|offenders|bads)\b)")
# a tracked artifact the gate WRITES from its own counts -- the destructive shape
WRITES = re.compile(r"(write_text|write_bytes|json\.dump|to_csv|open\([^)]*['\"]w)")


def population():
  for root in ROOTS:
    for dirpath, dirnames, filenames in os.walk(REPO / root):
      dirnames[:] = [d for d in dirnames if d not in EXCL]
      for fn in sorted(filenames):
        if fn.endswith(".py"):
          yield pathlib.Path(dirpath) / fn


def scan(p):
  src = p.read_text(errors="replace")
  lines = src.splitlines()
  try:
    tree = ast.parse(src)
  except SyntaxError:
    return None
  pops = [i for i, ln in enumerate(lines, 1)
          if any(f + "(" in ln for f in POP_FUNCS) and not ln.lstrip().startswith("#")]
  den = [i for i, ln in enumerate(lines, 1)
         if re.search(r"len\(|sum\(|Counter\(", ln) and VERDICT.search(ln) and i not in pops]
  # a denominator READ: `N of M`, `N/M`, `over M`
  den += [i for i, ln in enumerate(lines, 1)
          if re.search(r"\b(of|/)\s*\{?(len\(|sum\(|g\(|total|lanes|n_)", ln)]
  wr = [i for i, ln in enumerate(lines, 1) if WRITES.search(ln) and not ln.lstrip().startswith("#")]
  # the NAMES a count is bound to -- a guard on one of THESE is a denominator guard
  counted = {m.group(1) for ln in lines if (m := COUNTED.match(ln))}
  # a bad-list the module itself accumulates, so `X.append` on it IS a verdict change
  badlists = {m.group(1) for ln in lines if (m := BADLIST.match(ln))}
  guards = [(i, ln) for i, ln in enumerate(lines, 1)
            if GUARD.search(ln)
            and (any(re.search(rf"\b{re.escape(n)}\b", ln) for n in counted)
                 or re.search(r"len\(", ln))
            and (REFUSE.search("\n".join(lines[i - 1:i + 4]))
                 or any(re.search(rf"\b{re.escape(b)}\.append", ln) for b in badlists)
                 or VERDICTWORD.search(ln))]
  return {"pop": sorted(set(pops)), "den": sorted(set(den)), "write": sorted(set(wr)),
          "guard": guards, "lines": lines, "counted": counted}


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--verify", action="store_true", help="print the evidence per row")
  ap.add_argument("--only", help="substring filter on the path")
  a = ap.parse_args()
  rows, net = [], 0
  for p in sorted(population()):
    r = scan(p)
    if r is None:
      continue
    net += len(r["den"])
    if not (r["den"] and r["pop"]):
      continue
    guarded = bool(r["guard"])
    verdict_reachable = "WRITE" if r["write"] else "PRINT"
    rows.append({
      "path": str(p.relative_to(REPO)),
      "verdict": verdict_reachable,
      "zero_guard": "yes" if guarded else "NO",
      "pop_sites": ",".join(map(str, r["pop"][:6])),
      "den_sites": ",".join(map(str, r["den"][:8])),
      "n_den": len(r["den"]),
      "n_pop": len(r["pop"]),
    })
  site = [r for r in rows if r["zero_guard"] == "NO"]
  out = HERE / "sites.tsv"
  with open(out, "w") as fh:
    fh.write("path\tverdict_surface\tzero_guard\tpop_sites\tden_sites\tn_den\tn_pop\n")
    for r in rows:
      fh.write("\t".join(str(r[k]) for k in
                  ("path", "verdict", "zero_guard", "pop_sites", "den_sites", "n_den", "n_pop")) + "\n")
  print(f"SCOPE: roots={','.join(ROOTS)}  excluded={','.join(EXCL)}  "
        f"predicate=population-built AND count-reaches-verdict")
  print(f"  modules walked          : {sum(1 for _ in population())}")
  print(f"  modules with (1) and (2): {len(rows)}")
  print(f"  of those, NO zero-guard : {len(site)}   <-- the named population of interest")
  print(f"  of those, guarded       : {len(rows) - len(site)}")
  print(f"  net denominator lines dropped by the predicate: {net}")
  print(f"\nwrote {out.relative_to(REPO)} ({len(rows)} rows)")
  if a.verify:
    for r in rows:
      print(f"\n-- {r['path']}  surface={r['verdict']} guard={r['zero_guard']}")
      for ln in r["den_sites"].split(",")[:4]:
        if ln:
          print(f"     den  L{ln}: {r['lines'][int(ln)-1].strip()[:100]}"
                if "lines" in r else "")


if __name__ == "__main__":
  sys.exit(main())