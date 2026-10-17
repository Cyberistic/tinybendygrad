"""Emit sites.rows: every ABSENT named target, with its hand-adjudicated guard verdict.

`decided_by` is `READ` where I read the use site and its guard, and `CATEGORY` where the site
is a member of a family whose exemplar I read (cited in `evidence`).  A count that mixes the two
without saying so is exactly the "487 mutations / 25 unclassified" number this repo already
recorded once.  Nothing here is guessed.
"""
import pathlib, re

D = pathlib.Path(__file__).resolve().parent

# (instrument, target) -> (guarded, verdict, decided_by, evidence)
ADJ = {
 # ---------------- THE DEFECTS ----------------
 ("checks/gen_gate.py", "hdr.bend"): (
   "no", "DEFECT-ABSENT-UNGUARDED", "READ",
   "gen_gate.py:138 `HEADER = open(os.path.join(HERE, \"hdr.bend\")).read()` at COLUMN 0 "
   "(module level; main() is at :170). absent disk AND HEAD; `git log --all -- checks/hdr.bend` "
   "EMPTY (0 commits ever). NO guard of any kind: grep is_file|exists|refuse|exit(3)|"
   "SystemExit|FileNotFound|except over the whole file returns NOTHING. FileNotFoundError at "
   "import -> CPython exit 1 -> READS AS FAIL. Live consumer: "
   ".agents/slop/i64div/gate.sh:15 turns it into `GENERATOR FAILED` exit 1; "
   ".agents/slop/i64mul/census.py:18,87 subprocesses it. Already listed as 'libraries "
   "(no guard)' in .agents/slop/gatesrun/REPORT.md:22."),
 ("checks/classify.sh", ".agents/slop/mutledger/BLOBHIST.tsv"): (
   "no", "DEFECT-ABSENT-UNGUARDED", "READ",
   "classify.sh:20 `H=.agents/slop/mutledger/BLOBHIST.tsv`; the ONLY use is :26 "
   "`grep -q \"^$live\\t$b\\$\" \"$H\"`. absent disk AND HEAD (in 5 commits of history, "
   "5444ea42e and 4 siblings -- RECOVERABLE). The only `[ -f` in the file is :18 "
   "(pyproject.toml); there is no test of `$H` and no exit-3 arm for it. "
   "grep on a missing file exits 2, so the `else` at :27 fires and EVERY differing file is "
   "reported PLANT instead of STALE, and the script's exit status is the last printf = 0. "
   "GREEN AND WRONG, which is worse than FAIL. Contradicts its own header (:9-10)."),

 # ---------------- GUARDED, correct ----------------
 ("checks/rn-gate.py", ".agents/slop/xd1/render-gate-oracle.py"): (
   "yes", "GUARDED-REFUSED", "READ",
   "KNOWN-FIXED INSTANCE 1, CONFIRMED GUARDED: rn-gate.py:468-470 `if not a.oracle_stdout and "
   "not (REPO / ORACLE[0]).is_file(): refuse(...)` -> exit 3 (refuse at :77-84). Sits BEFORE "
   "the subprocess at :477. Target absent disk AND HEAD (0 commits ever)."),
 ("checks/rn-gate.py", "rn-port.txt"): (
   "yes", "GUARDED-REFUSED", "READ",
   "KNOWN-FIXED INSTANCE 2, CONFIRMED GUARDED: rn-gate.py:400-405 loops "
   "('rn-port.txt','rn-orc.txt') and `if not (HERE / _cap).is_file(): refuse(...)` -> exit 3, "
   "BEFORE the reads at :406-407. absent disk AND HEAD, 0 commits ever."),
 ("checks/rn-gate.py", "rn-orc.txt"): (
   "yes", "GUARDED-REFUSED", "READ",
   "KNOWN-FIXED INSTANCE 2, CONFIRMED GUARDED: same guard at rn-gate.py:400-405."),
 ("checks/vz_gate.py", "viz_oracle.py"): (
   "yes", "GUARDED-REFUSED", "READ",
   "KNOWN-FIXED INSTANCE 3, CONFIRMED GUARDED: vz_gate.py:74-77 `if not os.path.isfile(ORACLE): "
   "refuse(...)` -> exit 3 (:61-71), BEFORE the subprocess at :78. Target absent disk AND HEAD."),
 ("checks/nl-gate.py", "nl-port-post.txt"): (
   "yes", "GUARDED-REFUSED", "READ",
   "SAME FIX SHAPE, not previously in the brief: nl-gate.py:416-423 `_live = HERE / "
   "\"nl-port-post.txt\"; if not _live.is_file(): refuse(...)` -> exit 3, before the read. "
   "absent disk AND HEAD; `git log --all` answers nothing, and the comment says so."),
 ("checks/gate.py", "drive.mjs"): (
   "yes", "GUARDED-REFUSED", "READ",
   "gate.py:72-75 `for _p in (JS_LANE, HERE / \"drive.mjs\"): if not _p.is_file(): refuse(...)` "
   "-- one guard loop covering two declared inputs. Not previously reported."),
 ("gates/js-lane-census.py", "effect_runtime_shadow.bend"): (
   "yes", "GUARDED-REFUSED", "READ",
   "js-lane-census.py:85 CTL_BEND = ROOT/\"references/bend\"/.../effect_runtime_shadow.bend. "
   "GUARDED at :457-459 `for p in (JS_LANE, BEND, CTL_BEND, CTL_JS): if not p.exists(): return "
   "refuse(f\"input absent: {p}\")` -> REFUSED (:157-163). `references/` EXISTS on disk but the "
   "bend clone is not in it, so this is a real absent input that correctly REFUSES."),
 ("gates/js-lane-census.py", "effect_runtime_shadow.js"): (
   "yes", "GUARDED-REFUSED", "READ", "same guard at js-lane-census.py:457-459 (:86 CTL_JS)."),
 ("checks/gate.py", "dtype.probe.mjs"): (
   "n/a", "NOT-AN-INPUT-scratch", "READ",
   "gate.py:215 `(work / \"dtype.probe.mjs\").read_text()` reads a scratch probe the gate itself "
   "wrote into `work` two lines earlier, and the comparison that follows is the ASSERTION. "
   "A file the instrument produces is not an input it depends on."),

 # ---------------- NAMED BUT NEVER OPENED ----------------
 ("gates/datasets-oracle.py", "cifar-10-batches-bin/test_batch.bin"): (
   "n/a", "NOT-AN-INPUT-row-value", "READ",
   "datasets-oracle.py:38 `CIFAR_TEST`, used only at :99 `srow(\"dst_cifar_test\", CIFAR_TEST)` -- "
   "a STRING ROW describing a member of the downloaded tarball, used for counts and hashes. "
   "Never joined to a path, never opened. A path-SHAPED VALUE."),
 ("gates/datasets-oracle.py", "train-images-idx3-ubyte.gz"): (
   "n/a", "NOT-AN-INPUT-row-value", "CATEGORY",
   "same as CIFAR_TEST: the MN filenames in the MN table (datasets-oracle.py:27-28, 47-50)."),
 ("gates/datasets-oracle.py", "train-labels-idx1-ubyte.gz"): (
   "n/a", "NOT-AN-INPUT-row-value", "CATEGORY", "same family."),
 ("gates/datasets-oracle.py", "t10k-images-idx3-ubyte.gz"): (
   "n/a", "NOT-AN-INPUT-row-value", "CATEGORY", "same family."),
 ("gates/datasets-oracle.py", "t10k-labels-idx1-ubyte.gz"): (
   "n/a", "NOT-AN-INPUT-row-value", "CATEGORY", "same family."),
 ("checks/cites-census.py", "s.md"): (
   "n/a", "NOT-AN-INPUT-label", "READ",
   "cites-census.py:685 `lane_bcd(\"s.md\", [(1, ...)])`: `rel` is a tuple key for IN-MEMORY "
   "lines (lane_bcd at :295-303 never opens `rel`). A synthetic filename used as a label."),
 ("checks/slop-declare.py", "findings.md"): (
   "n/a", "NOT-AN-INPUT-name-set", "READ",
   "slop-declare.py:96 `DECLARATIONS = (\"report.md\", \"readme.md\", \"findings.md\", "
   "\"manifest.tsv\", \"manifest.rows\")` -- the file says so itself at :95: 'This is a name set, "
   "not a population'. The names are matched against directory listings, never opened."),
 ("checks/slop-declare.py", "readme.md"): ("n/a", "NOT-AN-INPUT-name-set", "CATEGORY", "same tuple."),
 ("checks/slop-declare.py", "manifest.rows"): ("n/a", "NOT-AN-INPUT-name-set", "CATEGORY", "same tuple."),
 ("checks/slop-declare.py", "manifest.tsv"): ("n/a", "NOT-AN-INPUT-name-set", "CATEGORY", "same tuple."),

 # ---------------- OUTPUTS OF A COMPILE, EXISTENCE-CHECKED ----------------
 ("checks/abi_gate.py", "abi_probe.js"): (
   "yes", "NOT-AN-INPUT-emitted", "READ",
   "abi_gate.py:371 `out, cmd = work / \"abi_probe.js\", [...]` -- the target of `bend -o`, and "
   ":376 `if r.returncode != 0 or not out.exists():` separates REFUSED from DEAD. An OUTPUT, "
   "and its absence is a verdict."),
 ("checks/abi_gate.py", "abi_probe.gen.c"): (
   "yes", "NOT-AN-INPUT-emitted", "READ", "same, abi_gate.py:373-376."),
 ("checks/gate_norm.py", "gate_norm.js"): (
   "yes", "NOT-AN-INPUT-emitted", "READ",
   "gate_norm.py:119 `js, c = work / \"gate_norm.js\", work / \"gate_norm.c\"` are `bend -o` "
   "targets; :123 `if not js.exists():` separates REFUSED from DEAD."),
 ("checks/gate_norm.py", "gate_norm.c"): ("yes", "NOT-AN-INPUT-emitted", "CATEGORY", "same."),

 # ---------------- PLANTS AND NEGATIVE CONTROLS: ABSENCE IS THE POINT ----------------
 ("checks/env-precond.py", "absent.txt"): (
   "n/a", "PLANT-negative-control", "CATEGORY",
   "env-precond.py:420 -- the instrument's subject is the ABSENCE of a precondition; a file "
   "named absent.txt that is absent is the control, not a missing input."),
 ("checks/substrate-id.py", "does-not-exist.txt"): (
   "n/a", "PLANT-negative-control", "CATEGORY", "substrate-id.py:568, same shape."),
 ("gates/gate-surface.py", "claimed.py"): (
   "n/a", "PLANT-negative-control", "CATEGORY", "gate-surface.py:787, same family."),
 ("gates/gatekit.py", "unused.py"): (
   "n/a", "PLANT-negative-control", "CATEGORY",
   "gatekit.py:271 -- `unused.py`/`unused.bend`: the ORACLE-SIDE FIXTURES of the five-exit "
   "template gatekit documents (AGENTS.md doctrine 2). Absent on disk because nothing ran."),
 ("gates/gatekit.py", "unused.bend"): ("n/a", "PLANT-negative-control", "CATEGORY", "same tuple."),
 ("gates/runner.py", "lost-gate.py"): (
   "n/a", "PLANT-negative-control", "CATEGORY", "runner.py:422 -- a gate that no longer exists."),
 ("gates/runner.py", "g.bend"): ("n/a", "PLANT-scratch", "CATEGORY", "runner.py:421, scratch fixture."),
 ("checks/gatesweep.py", "skip-gate.py"): (
   "n/a", "PLANT-state-fixture", "CATEGORY",
   "gatesweep.py:292 -- one fixture per SKIP state; SKIP must be producible, so the file is made "
   "by the harness. NOTE: this is gatesweep's OWN synthetic skip-gate, not a claim about a "
   "checked-in gate."),
 ("gates/oracle-census-gate.py", "x.py"): (
   "n/a", "PLANT-orphan-fixture", "CATEGORY", "oracle-census-gate.py:577, an oracle with no gate."),
 ("gates/citations-census-gate.py", "plant.md"): (
   "n/a", "PLANT-negative-control", "CATEGORY", "citations-census-gate.py:799."),
 ("gates/citations-census-gate.py", "nonesuch.bend"): (
   "n/a", "PLANT-negative-control", "CATEGORY", "citations-census-gate.py:810."),
 ("gates/docnum-census.py", "p.md"): ("n/a", "PLANT-fixture", "CATEGORY", "docnum-census.py:489."),
 ("gates/docnum-census.py", "r.bend"): ("n/a", "PLANT-fixture", "CATEGORY", "docnum-census.py:491."),
 ("checks/cl-port-gate.py", "oracle_planted.py"): (
   "n/a", "PLANT", "CATEGORY", "cl-port-gate.py:223; the name declares it."),
 ("checks/jsfix_gate.py", "div.gen.c"): ("n/a", "PLANT-emitted", "CATEGORY",
   "jsfix_gate.py:349, in the 78-hit plant/write family."),
 ("checks/jsfix_gate.py", "seam.bend"): ("n/a", "PLANT", "CATEGORY", "jsfix_gate.py:377."),
 ("checks/runs-artifacts.py", "a.sh"): ("n/a", "PLANT-fixture", "CATEGORY",
   "runs-artifacts.py:989 `lane(\"a.sh\", \"#!/bin/sh\\nmkdir -p runs/x\\n\")` -- the lane "
   "helper WRITES the file. a,b,c,f,g,h,i.sh are eight of a nine-lane fixture set."),
 ("checks/runs-artifacts.py", "b.sh"): ("n/a", "PLANT-fixture", "CATEGORY", "runs-artifacts.py:991."),
 ("checks/runs-artifacts.py", "c.sh"): ("n/a", "PLANT-fixture", "CATEGORY", "runs-artifacts.py:993."),
 ("checks/runs-artifacts.py", "f.sh"): ("n/a", "PLANT-fixture", "CATEGORY", "runs-artifacts.py:1003."),
 ("checks/runs-artifacts.py", "g.sh"): ("n/a", "PLANT-fixture", "CATEGORY", "runs-artifacts.py:1005."),
 ("checks/runs-artifacts.py", "h.sh"): ("n/a", "PLANT-fixture", "CATEGORY", "runs-artifacts.py:1007."),
 ("checks/runs-artifacts.py", "i.sh"): ("n/a", "PLANT-fixture", "CATEGORY", "runs-artifacts.py:1010."),
 ("checks/run-f64.sh", "run.c"): ("n/a", "PLANT-scratch", "CATEGORY",
   "run-f64.sh -- `run.c`/`kernel.c` live under the script's own scratch `$W` workdir "
   "(\"$W/a.log\", \"$W/a/cc-run.log\"); the script builds and compiles them."),
 ("checks/run-f64.sh", "kernel.c"): ("n/a", "PLANT-scratch", "CATEGORY", "same scratch workdir."),
 ("checks/run-f64.sh", "mm-rows.txt"): ("n/a", "PLANT-emitted", "CATEGORY",
   "run-f64.sh:~107 `oracle_f64.build(out / \"mm-rows.txt\")` inside a patch string -- an output."),

 # ---------------- THE -mutate.py FAMILY: every member self-writes ----------------
 ("gates/amd_dsl_census-mutate.py", "dsl-mut.bend"): ("n/a", "PLANT-self-written", "READ",
   "amd_dsl_census-mutate.py:81 `MUT_PORT`, in COPIES (:85); :164-166 `_clean()` does "
   "`p.unlink(missing_ok=True)` and `write_copies` writes EVERY member. The docstring says why: "
   "'a missing one is a REFUSED exit for the wrong reason'."),
 ("gates/amd_dsl_census-mutate.py", "amd-mut-oracle.py"): ("n/a", "PLANT-self-written", "READ", "amd_dsl_census-mutate.py:81,82 COPIES."),
 ("gates/amd_dsl_census-mutate.py", "amd-mut-pins.rows"): ("n/a", "PLANT-self-written", "READ", "amd_dsl_census-mutate.py:82,85."),
 ("gates/amd_dsl_census-mutate.py", "amd-mut-gate.py"): ("n/a", "PLANT-self-written", "READ", "amd_dsl_census-mutate.py:83,85."),
 ("gates/amd_dsl_census-mutate.py", "amd-mut-run.py"): ("n/a", "PLANT-self-written", "READ", "amd_dsl_census-mutate.py:84,85."),
 ("gates/crp_graph_census-mutate.py", "crp-mut-driver.bend"): ("n/a", "PLANT-self-written", "CATEGORY", "crp_graph_census-mutate.py:72, the amd_dsl COPIES mechanism."),
 ("gates/crp_graph_census-mutate.py", "crp-mut-oracle.py"): ("n/a", "PLANT-self-written", "CATEGORY", "crp_graph_census-mutate.py:73."),
 ("gates/crp_graph_census-mutate.py", "crp-mut-pins.rows"): ("n/a", "PLANT-self-written", "CATEGORY", "crp_graph_census-mutate.py:74."),
 ("gates/crp_graph_census-mutate.py", "crp-mut-gate.py"): ("n/a", "PLANT-self-written", "CATEGORY", "crp_graph_census-mutate.py:76."),
 ("gates/crp_graph_census-mutate.py", "crp-mut-run.py"): ("n/a", "PLANT-self-written", "CATEGORY", "crp_graph_census-mutate.py:77."),
 ("gates/cstyle_render_census-mutate.py", "cstyle-mut.bend"): ("n/a", "PLANT-self-written", "CATEGORY", "cstyle_render_census-mutate.py:56."),
 ("gates/cstyle_render_census-mutate.py", "cstyle-mut-driver.bend"): ("n/a", "PLANT-self-written", "CATEGORY", "cstyle_render_census-mutate.py:57."),
 ("gates/decomp_graph_census-mutate.py", "decomp-mut-driver.bend"): ("n/a", "PLANT-self-written", "CATEGORY", "decomp_graph_census-mutate.py:77."),
 ("gates/decomp_graph_census-mutate.py", "dtype-mut.bend"): ("n/a", "PLANT-self-written", "CATEGORY", "decomp_graph_census-mutate.py:80."),
 ("gates/decomp_graph_census-mutate.py", "op-mut.bend"): ("n/a", "PLANT-self-written", "CATEGORY", "decomp_graph_census-mutate.py:81."),
 ("gates/realize_graph_census-mutate.py", "realize-mut.bend"): ("n/a", "PLANT-self-written", "CATEGORY", "realize_graph_census-mutate.py:106."),
 ("gates/realize_graph_census-mutate.py", "realize-mut-driver.bend"): ("n/a", "PLANT-self-written", "CATEGORY", "realize_graph_census-mutate.py:107."),
 ("gates/realize_graph_census-mutate.py", "realize-mut-oracle.py"): ("n/a", "PLANT-self-written", "CATEGORY", "realize_graph_census-mutate.py:108."),
 ("gates/ptx_render_census-mutate.py", "_ptxmut.bend"): ("n/a", "PLANT-self-written", "CATEGORY", "ptx_render_census-mutate.py:61."),
 ("gates/ptx_render_census-mutate.py", "_ptxaxis_mut.bend"): ("n/a", "PLANT-self-written", "CATEGORY", "ptx_render_census-mutate.py:64."),
 ("gates/tc_ptx_types-mutate.py", "_tcptxmut.bend"): ("n/a", "PLANT-self-written", "CATEGORY", "tc_ptx_types-mutate.py:35."),
 ("gates/tc_ptx_types-mutate.py", "_tcptx_types_mut.bend"): ("n/a", "PLANT-self-written", "CATEGORY", "tc_ptx_types-mutate.py:37."),
 ("gates/optim-nop-mutate.py", "optim-mut.bend"): ("n/a", "PLANT-self-written", "CATEGORY", "optim-nop-mutate.py:182."),

 # ---------------- SELF-PRODUCED PROBES ----------------
 ("checks/demo.sh", "tinybendygrad/runtime/PROBE-SELFDEMO.bend"): ("n/a", "SELF-WRITTEN", "READ",
   "demo.sh:21 `PLANT=...`; :43 `printf 'import Base\\n...' > \"$PLANT\"` writes it, :48 `rm -f` "
   "removes it, :56 re-checks with `[ -e ]`. A probe, not an input."),
 ("checks/demo.sh", "PROBE-SELFDEMO.bend"): ("n/a", "SELF-WRITTEN", "CATEGORY", "same, bare-name spelling at :56."),
 ("checks/demo.sh", "tinybendygrad/runtime/ops_bend.mut.bend"): ("n/a", "DELETION-BY-DESIGN", "READ",
   "demo.sh:49 `rm -f tinybendygrad/runtime/ops_bend.mut.bend` under the heading 'THE PLANT THIS "
   "UNIT OWNS DELETED'. `rm -f` cannot fail on absence."),
 ("checks/demo.sh", "ops_bend.mut.bend"): ("n/a", "DELETION-BY-DESIGN", "CATEGORY", "same, bare-name spelling."),
 ("checks/demo.sh", "runtime/ops_bend.mut.bend"): ("n/a", "DELETION-BY-DESIGN", "CATEGORY",
   "demo.sh -- third spelling of the same path; all three are the same rm -f / [ -e ] target."),
 ("checks/disarm.sh", "tinybendygrad/runtime/PROBE-DISARM.bend"): ("n/a", "SELF-WRITTEN", "READ",
   "disarm.sh:19 `PROBE=...`; :34 `printf 'import Base\\n...' > \"$PROBE\"`; :46 `rm -f`; "
   ":53 `[ -e \"$PROBE\" ]`."),
 ("checks/disarm.sh", "PROBE-DISARM.bend"): ("n/a", "SELF-WRITTEN", "CATEGORY", "same, bare-name spelling at :53."),
}

PLANTWIN = re.compile(r"write_text|write_bytes|unlink|mkdir|mkdtemp|TemporaryDirectory|"
                      r"shutil\.copy|shutil\.move|\.write\(|open\([^)]*[\"'][wax]|copy2|copytree|"
                      r"touch|rm -f|cat >|cp |mv ")
ROOT = pathlib.Path(__file__).resolve().parents[3]
_cache = {}


def self_written(inst, tgt):
  """The instrument CREATES the file. +-400 chars around a mention of the basename, searched
  for a create/remove verb. This is what disposes of the 87 fixture vocabularies
  (`good.py`, `victim.py`, `keeper.py`, `nope.txt`, `d.sh`, ...) in one reproducible pass rather
  than 87 readings -- and it can only ever turn a row INTO a plant, never manufacture an
  external finding, because every row it touches is own-directory absent."""
  if inst not in _cache:
    _cache[inst] = (ROOT / inst).read_text(errors="replace")
  src = _cache[inst]
  base = tgt.rsplit("/", 1)[-1]
  for m in re.finditer(re.escape(base), src):
    if PLANTWIN.search(src[max(0, m.start() - 400): m.end() + 400]):
      return True
  return False


rows = []
seen = set()
for line in (D / "sites.raw.out").read_text().splitlines():
  inst, ln, tgt, d, h, cls, suf, dirn, wr = line.split("\t")
  if d == "yes" or h == "yes" or suf != "-" or dirn != "-":
    continue  # only ABSENT, all-signals-negative rows are sites
  rows.append((inst, ln, tgt, d, h, cls, wr))

out = []
for inst, ln, tgt, d, h, cls, wr in rows:
  key = (inst, tgt)
  if key in ADJ:
    g, v, how, ev = ADJ[key]
  elif self_written(inst, tgt):
    g, v, how, ev = ("n/a", "PLANT-self-written", "PLANTWIN",
                     f"{inst} CREATES {tgt.rsplit('/', 1)[-1]}: a write/create verb lies within "
                     f"400 chars of a mention (reproducible: rows.py self_written()). It is a "
                     "fixture, so its absence is the intended state, not a missing input.")
  else:
    g, v, how, ev = ("REFUSED", "UNADJUDICATED", "NONE",
                     "no adjudication recorded -- see REPORT.md 'what I could not determine'")
  out.append((inst, tgt, d, h, g, v, how, ev, ln, cls))
  seen.add(key)

out.sort(key=lambda r: (r[5], r[0], r[1]))
with open(D / "sites.rows", "w") as fh:
  fh.write("# absent-input census -- checks/ and gates/ instruments naming an ABSENT external "
           "or own-directory input\n")
  fh.write("# HEAD 444890672d9baebb6309952495f480623f481fc5; columns:\n")
  fh.write("# instrument \\t target \\t exists_disk \\t exists_HEAD \\t guarded \\t verdict "
           "\\t evidence\n")
  for inst, tgt, d, h, g, v, how, ev, ln, cls in out:
    fh.write(f"{inst}\t{tgt}\t{d}\t{h}\t{g}\t{v}\t{how}\t{ev}\n")

missing = [k for k in ADJ if k not in seen]
print(f"rows\t{len(out)}")
print(f"instruments\t{len({r[0] for r in out})}")
from collections import Counter
for k, n in sorted(Counter(r[5] for r in out).items(), key=lambda x: -x[1]):
  print(f"  {k}\t{n}")
print("decided_by\t" + str(Counter(r[6] for r in out)))
print("ADJ entries with no matching row (check for drift)\t" + (str(missing) if missing else "none"))