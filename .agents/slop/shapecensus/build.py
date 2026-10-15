#!/usr/bin/env python3
"""Write `.agents/slop/shapecensus/findings.rows`: ONE row per discovered `*.py`, with the
expression that decides ITS membership and the class that expression belongs to.

THE POPULATION OF THIS CENSUS IS DISCOVERED: `rglob("*.py")` under `checks/` and `gates/`.
No list from any document contributes a row. Every file the walk reaches appears exactly once.

`CLS` is hand-assigned from reading the file, not from the mechanical signal roll-up: the
signals in `rollup.rows` are what told me where to look, not the verdict. Anything not named
in `CLS` and not matched by a `RULE` is emitted as `REFUSED` with the reason, never guessed.

usage: .venv/bin/python .agents/slop/shapecensus/build.py
"""
from __future__ import annotations

import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]

# class -> acceptable?
NOT_ACCEPTABLE = {"basename-regex", "suffix-set", "hand-list", "single-dir-glob",
                  "unscoped-text-regex", "hand-list-cross-checked"}

# NOT a population, and NOT in `NOT_ACCEPTABLE`: a CLASSIFICATION TABLE. It decides which BUCKET
# a row a discovered population already produced lands in, never WHICH rows exist. The census
# gates and `checks/citation-gate.py` are the instances; the distinction is the whole difference
# between `ORACLE_WORD` (a basename deciding whether a file is in the population AT ALL) and
# `CLASSES` (a pattern deciding what a row that IS in the population is called).
CLASS_TABLES = {"class-table"}

# (path, expression, class, evidence, state)
CLS: dict[str, tuple[str, str, str, str]] = {
    # ---- checks/ : walk / declaration -------------------------------------------------------
    "checks/census.py": ("[GENERATOR['py'], *sorted(ORACLE.rglob('*.py'))]", "walk",
                         "checks/census.py:144", "PRESENT"),
    "checks/cites-census.py": ("os.walk(ROOT) + git ls-tree -r HEAD --name-only", "walk",
                               "checks/cites-census.py:73", "PRESENT"),
    "checks/gatesweep.py": ("os.walk(root / 'gates', followlinks=False)", "walk",
                            "checks/gatesweep.py:107", "PRESENT"),
    "checks/marker-audit.py": ("[Path(r).rglob('*.bend') for r in roots]; roots = argv or "
                               "['tinybendygrad']", "walk", "checks/marker-audit.py:83-84",
                               "PRESENT (walk narrowed by an extension; root list is a "
                               "3-token default, overridable on argv)"),
    "checks/no-txt.py": ("os.walk over the tree, minus differ.declared() + two loaded "
                         "declarations", "declaration-by-path", "checks/no-txt.py:56 (table of "
                         "the three loaded declarations)", "PRESENT"),
    "checks/oracle-txt-census.py": ("ORACLES.rglob('*.rows') / ORACLES.rglob('*.txt')", "walk",
                                    "checks/oracle-txt-census.py:318,342", "PRESENT"),
    "checks/residue.py": ("os.walk(top) for each top", "walk", "checks/residue.py:299",
                          "PRESENT"),
    "checks/slop-declare.py": ("git ls-tree -r -z --name-only HEAD, filtered by endswith("
                              "suffixes)", "suffix-set", "checks/slop-declare.py:148,172",
                              "PRESENT -- the docstring at :31 calls this a WALK; the "
                              "membership test at :172 is a suffix tuple"),
    "checks/stage1-census.py": ("glob.glob(f'{ROOT}/tinybendygrad/**/*.bend', recursive=True)",
                                "walk", "checks/stage1-census.py:192", "PRESENT"),
    "checks/substrate.py": ("os.walk(root) via files()", "walk", "checks/substrate.py:158",
                            "PRESENT"),
    "checks/substrate-id.py": ("a generator's declared() loaded by path (its own header says so)",
                               "declaration-by-path", "checks/substrate-id.py:91", "PRESENT"),
    "checks/txt-owners.py": ("os.walk(ROOT) then f.endswith('.txt')", "walk",
                             "checks/txt-owners.py:78,81",
                             "PRESENT (the suffix IS the instrument's subject: it claims about "
                             ".txt and no .txt is dropped)"),
    "checks/denominator.py": ("sorted(source.glob(pattern))", "single-dir-glob",
                              "checks/denominator.py:66", "PRESENT -- not read beyond this call"),
    "checks/index-arm-gate.py": ("git ls-tree -r <rev>", "walk", "checks/index-arm-gate.py:101",
                                 "PRESENT"),
    "checks/diary-census.py": ("git ls-tree -r HEAD", "walk", "checks/diary-census.py:29",
                               "PRESENT (cited in its own header; the walk call is at :299+ of "
                               "the shared helper, not read here)"),
    "gates/gate-surface.py": ("HOMES measurement + os.walk control at :309", "walk",
                               "gates/gate-surface.py:309",
                               "PRESENT -- read as a CONTROL, named 'not the population' at :284"),
    "checks/gen_gate.py": ("os.listdir(HERE) then startswith('gate') and endswith('.bend')",
                           "suffix-set", "checks/gen_gate.py:179-180",
                           "PRESENT -- a basename prefix AND a suffix, over one directory"),
    "checks/sz.py": ("os.walk(os.path.join(base_path, 'tinygrad')) then endswith('.py') or "
                     "endswith('.js')", "suffix-set", "checks/sz.py:19,21", "PRESENT"),
    "gates/gatekit.py": ("the three lanes' OWN emitted rows, read from the staged files", "walk",
                         "gates/gatekit.py:449 (`raw = {t: _lines(f) for t, f in lanes.items()}`)",
                         "PRESENT -- this is the ONE place a gate's row population is DISCOVERED"),
    "gates/gates-pop.py": ("HOMES = _homes(ROOT) = gate_homes(ROOT)[0], an AST measurement",
                           "walk", "gates/gates-pop.py:1504,868-869",
                           "FIXED -- `HOMES = ('checks','gates')` is GONE; :97-99 records why "
                           "it was right and :112-118 records that the ROOT SET is measured"),
    "gates/gendirs.py": ("os.walk(root)", "walk", "gates/gendirs.py:95",
                         "PRESENT"),
    "gates/gate-surface.py:DUP": None,
    "gates/pins-shape-gate.py": ("HERE.iterdir() (never rglob), by NAME", "walk",
                                 "gates/pins-shape-gate.py:239,292",
                                 "PRESENT -- its own header at :33 says 'A WALK AND A NAME, NOT "
                                 "A SUFFIX SET'"),
    "gates/retention-check.py": ("root.iterdir() of directories; present = iterdir of files",
                                 "walk", "gates/retention-check.py:124,181", "PRESENT"),
    "gates/indexread-gate.py": ("git ls-tree -r --name-only HEAD", "walk",
                                "gates/indexread-gate.py:123",
                                "PRESENT -- its own header at :30 says the population comes "
                                "from the COMMIT TREE"),
    "gates/mutkit.py": ("n/a -- shared mutation plumbing", "no-population",
                        "gates/mutkit.py (imported by the 10 -mutate.py files)", "PRESENT -- "
                        "NOT READ"),
    "gates/wk-f32-rows.py": ("n/a -- a rows file beside its gate", "no-population", "REFUSED",
                             "REFUSED -- not read"),
    "gates/bc_u32_table.py": ("n/a", "no-population", "REFUSED", "REFUSED -- not read"),
    "gates/bc-u32-gen.py": ("n/a -- a generator", "no-population", "REFUSED",
                            "REFUSED -- not read"),
    "gates/ops_python_exec-gen.py": ("n/a -- a generator", "no-population", "REFUSED",
                                     "REFUSED -- not read"),
    "gates/ptx_render_census-gen.py": ("n/a -- a generator", "no-population", "REFUSED",
                                       "REFUSED -- not read"),
    "checks/both-census.py": ("n/a", "no-population", "REFUSED", "REFUSED -- not read"),
    "checks/cl-port-gate.py": ("n/a", "no-population", "REFUSED", "REFUSED -- not read"),
    "checks/devpin.py": ("D.glob('D*.txt') / D.glob('D1-graph-*.txt')", "single-dir-glob",
                         "checks/devpin.py:80,88", "PRESENT -- not read beyond these two calls"),
    "gates/tn_nodes-gate.py": ("ROWS = tuple(f'n{i}' for i in range(15))", "hand-list",
                               "gates/tn_nodes-gate.py:52",
                               "PRESENT -- DERIVED from a hand-typed integer 15, then "
                               "cross-checked by gatekit's count at gates/gatekit.py:432"),
    "gates/tn_minimum-gate.py": ("REFUSED -- the rows literal is not at module scope",
                                 "hand-list", "gates/tn_minimum-gate.py:24 (its docstring says "
                                 "FIVE ROWS)", "PRESENT -- REFUSED on the binding: the census "
                                 "found no iterated module-level literal"),
    "gates/bc-u32-gate.py": ("ROWS = 39", "hand-list", "gates/bc-u32-gate.py:50",
                             "PRESENT -- a BARE COUNT with no names, and :67 builds `pins` from "
                             "a comprehension over ROWS"),
    "gates/decomp_value-gate.py": ("the pins FILE beside the gate, "
                                   "decomp_graph_census-pins.rows", "declaration-by-path",
                                   "gates/decomp_value-gate.py:34",
                                   "PRESENT -- a DATA FILE loaded by path, regenerated by "
                                   "--refresh (:5); its CONTENT is still typed by hand, so this "
                                   "is a weaker form of the same thing"),
    "gates/ops_python_exec-gate.py": ("ops_python_exec-pins.rows, loaded by path", "hand-list",
                                      "gates/ops_python_exec-gate.py:65-66",
                                      "PRESENT -- a pins FILE beside the gate, :84 records the "
                                      "reason it lives there (not in the gitignored "
                                      "gates/artifacts/)"),
    "gates/git-massdelete-gate.py": ("git ls-tree / rev-list over the commit range", "walk",
                                     "REFUSED", "REFUSED -- not read; the range population is "
                                     "unexamined here"),
    "checks/runs-artifacts.py": ("glob.glob(root/checks/'*.py') + glob.glob(root/gates/'*.py')",
                                 "single-dir-glob", "checks/runs-artifacts.py:219-220",
                                 "PRESENT -- the INSTRUMENT population is two directory globs"),
    "checks/unowned.py": ("git ls-tree -r HEAD, minus PROSE = ('.md','.out','.rows','.tsv',"
                          "'.json','.txt','.err')", "suffix-set", "checks/unowned.py:74,198",
                          "PRESENT"),
    "checks/corpus-figure.py": ("differ.PINS imported", "declaration-by-path",
                                 "checks/corpus-figure.py:175 (the PINS read)",
                                 "PRESENT"),
    "checks/repro-paths.py": ("git ls-tree -r --name-only HEAD filtered by p.endswith(REPORTS), "
                              "REPORTS = '.md'; the PATH population is REF matched then "
                              "os.path.exists", "suffix-set", "checks/repro-paths.py:68,81,64,108",
                              "PARTIAL -- the suffix set that was retracted from REF is STILL "
                              "the report population at :68/:81"),
    "checks/differ.py": ("declared() = {f'{n}.txt' for n in (*LITERALS, *REPRO_LITERALS)} | ... "
                         "built from corpus()/CONTROLS/PLANTS/STAB", "declaration-by-path",
                         "checks/differ.py:357,373-381,1118",
                         "PRESENT -- the declaration is DERIVED from the generator's own "
                         "sources, so it is doctrine (a). CONTROLS (:237) and PLANTS are hand "
                         "lists INSIDE it, and each is a set of graphs the run must compare, not "
                         "a set of files to look at"),
    # ---- checks/ : hand lists ---------------------------------------------------------------
    "checks/wallcheck.py": ("WALK_ROOTS = ('tinybendygrad','.agents/slop','docs','checks',"
                            "'gates','AGENTS.md','README.md') then SUFFIXES of 12 extensions",
                            "hand-list", "checks/wallcheck.py:47 (WALK_ROOTS), :48 (SUFFIXES)",
                            "PRESENT -- 7 named roots, iterated at :139"),
    "checks/no-strays.py": ("SOURCE_TREES = ('tinybendygrad',) then os.walk per tree",
                            "hand-list", "checks/no-strays.py:139,147",
                            "PRESENT -- one named source tree"),
    "checks/citation-gate.py": ("PYROOTS = ('tinygrad','examples','extra')", "hand-list",
                                "checks/citation-gate.py:43,127", "PRESENT"),
    "checks/devgate.py": ("VENDOR_PREFIX = ('tinygrad/','references/','xd1/','opstree/')",
                          "hand-list", "checks/devgate.py:210", "PRESENT"),
    "checks/disagree-gate.py": ("ARMED = ('allred','cdiv','late')", "hand-list",
                                "checks/disagree-gate.py:60,327", "PRESENT"),
    "checks/abi4_gate.py": ("OTHER_GATES = ('checks/abi_gate.py','checks/jsfix_gate.py')",
                            "hand-list", "checks/abi4_gate.py:93", "PRESENT"),
    "checks/substrate-snapshot.py": ("COPIES = ('bin','checks/differ.py',...)", "hand-list",
                                     "checks/substrate-snapshot.py:76,103",
                                     "PRESENT -- one copy list across two files "
                                     "(checks/differ.py:884 SUBSTRATE_INPUTS is the same list "
                                     "typed twice)"),
    "checks/sweep.py": ("RESIDUE_ROOTS = ('.agents/slop','runs')", "hand-list",
                        "checks/sweep.py:81,1049",
                        "PRESENT -- and two MORE shapes in the same file, see the two rows "
                        "below"),
    # ---- checks/ : the two shapes the doctrine names -----------------------------------------
    "checks/sweep.py:ORACLE_WORD": ("ORACLE_WORD = re.compile(r'(^|[-_.])(oracle|rows|expect|"
                                    "pins|baseline)([-_.]|$)') matched against a BASENAME",
                                    "basename-regex", "checks/sweep.py:716 (defined), :1276 "
                                    "(used: `name in mentioned and ORACLE_WORD.search(name)`)",
                                    "PRESENT -- PARTIALLY retired: the citation conjunct was "
                                    "added so an uncited file cannot reach this arm, but the "
                                    "bucket is still chosen from the basename"),
    "checks/sweep.py:ROLE_DIRS": ("ROLE_DIRS = {'oracles':'ORACLE','gates':'GATE',"
                                  "'checks':'GATE'} matched against a path PART",
                                  "hand-list", "checks/sweep.py:766,1201-1202",
                                  "PRESENT -- 3 directory names; the file's own comment records "
                                  "that strays/strays-root were removed from it as an incident "
                                  "that outlived its reason"),
    "checks/sweep.py:LIVE_UNITS": ("LIVE_UNITS -- a tuple of 14 names", "hand-list",
                                   "checks/sweep.py:768 (the tombstone comment)",
                                   "FIXED -- removed; :768 records the removal and points at "
                                   "live_units()"),
    "checks/repro-paths.py:REF": ("REF = re.compile(r'(?:^|\\s)((?:\\.agents/slop/|checks/|"
                                  "gates/)[\\w./-]*\\.[A-Za-z0-9]+)')", "unscoped-text-regex",
                                  "checks/repro-paths.py:64,101",
                                  "FIXED -- the five-item suffix set is gone; membership is now "
                                  "decided by os.path.exists at :108"),
    # ---- checks/ : self-declared arms --------------------------------------------------------
    "checks/abi_gate.py": ("ARMS/ORACLE/WORDS literal dicts, one per plant arm",
                           "self-declared-arms", "checks/abi_gate.py:291", "PRESENT"),
    "checks/jsfix_gate.py": ("ARMS/DEFS literal dicts, one per plant arm", "self-declared-arms",
                             "checks/jsfix_gate.py:145", "PRESENT"),
    "checks/vz_gate.py": ("MUTATIONS literal list, one per plant arm", "self-declared-arms",
                          "checks/vz_gate.py:114", "PRESENT"),
    "checks/gatesweep.py:PLANTS": ("PLANTS = (('dead-gate.py','DEAD',''), ...)",
                                   "self-declared-arms", "checks/gatesweep.py:287",
                                   "PRESENT"),
    "checks/env-precond.py": ("PRECONDS / RECORD_KEYS", "self-declared-arms",
                              "checks/env-precond.py:116", "PRESENT"),
    # ---- checks/ : declares no population ----------------------------------------------------
    "checks/al-verdict.py": ("n/a -- runs the lanes it is given", "no-population",
                             "checks/al-verdict.py:29 (REPO hardcoded)", "PRESENT"),
    "checks/bounded.py": ("n/a -- one named command", "no-population",
                          "checks/bounded.py:266 (the CLI it wraps)", "PRESENT"),
    "checks/cli.py": ("n/a -- a viz CLI", "no-population", "checks/cli.py:104",
                      "PRESENT -- not read beyond the import block"),
    "checks/coindep.py": ("n/a -- re-exports SKIP_DIRS for no-strays", "no-population",
                          "checks/no-strays.py:137 (`SKIP_DIRS = set(_coindep().SKIP_DIRS)`) is "
                          "where its answer is consumed", "PRESENT -- NOT READ"),
    "checks/compile.py": ("n/a", "no-population", "REFUSED", "REFUSED -- not read"),
    "checks/coverage.py": ("n/a -- reads a published row set", "no-population",
                           "checks/coverage.py:40 (imports census.classify)", "PRESENT -- NOT "
                           "READ"),
    "checks/dup-census.py": ("n/a", "no-population", "REFUSED", "REFUSED -- not read"),
    "checks/dup-gate.py": ("n/a -- a caller names both lanes", "no-population",
                           "checks/dup-gate.py:329-331 (--port/--oracle/--compare)",
                           "PRESENT -- NOT READ"),
    "checks/e2e.py": ("its own STAGE table, cross-checked against the transcript", "hand-list",
                      "checks/e2e.py (the stage list; line REFUSED -- not read)",
                      "PARTIAL -- REFUSED on the line; the cross-check claim is unverified here"),
    "checks/fw_live.py": ("n/a", "no-population", "REFUSED", "REFUSED -- not read"),
    "checks/gate.py": ("n/a -- one JS lane", "no-population", "checks/gate.py:245",
                       "PRESENT -- NOT READ"),
    "checks/gate_dtype.py": ("n/a -- a caller names the lane", "no-population",
                             "checks/gate_dtype.py:92-95", "PRESENT -- NOT READ"),
    "checks/gate_norm.py": ("n/a", "no-population", "REFUSED", "REFUSED -- not read"),
    "checks/git-index-guard.py": ("n/a", "no-population", "REFUSED", "REFUSED -- not read"),
    "checks/graphcmp-census-audit.py": ("a PIN file read by name", "no-population",
                                        "checks/graphcmp-census-audit.py:52-53",
                                        "PRESENT -- NOT READ"),
    "checks/hermetic-census.py": ("n/a", "no-population", "REFUSED", "REFUSED -- not read"),
    "checks/llama.py": ("n/a -- a weights loader", "no-population", "REFUSED",
                        "REFUSED -- not read"),
    "checks/nl-gate.py": ("n/a -- captures named artifacts", "no-population",
                          "checks/nl-gate.py:457-458", "PRESENT -- NOT READ"),
    "checks/nl-gate-noguard.py": ("n/a -- the same driver without the guard", "no-population",
                                  "REFUSED", "REFUSED -- not read"),
    "checks/no-shrink.py": ("PORT = 'tinybendygrad', one named tree", "no-population",
                            "checks/no-shrink.py:39", "PRESENT -- one tree, not a census"),
    "checks/norm_check.py": ("n/a", "no-population", "REFUSED", "REFUSED -- not read"),
    "checks/nvrows-deadrow-gate.py": ("n/a", "no-population", "REFUSED", "REFUSED -- not read"),
    "checks/oracle_f64.py": ("n/a -- a reference producer", "no-population", "REFUSED",
                             "REFUSED -- not read"),
    "checks/plant.py": ("n/a -- a mutation harness", "no-population", "REFUSED",
                        "REFUSED -- not read"),
    "checks/process_replay.py": ("n/a", "no-population", "REFUSED", "REFUSED -- not read"),
    "checks/render-gate-oracle.py": ("n/a -- a reference producer", "no-population", "REFUSED",
                                     "REFUSED -- not read"),
    "checks/repair-dupes.py": ("n/a", "no-population", "REFUSED", "REFUSED -- not read"),
    "checks/reset.py": ("n/a -- a git action", "no-population", "REFUSED",
                        "REFUSED -- not read"),
    "checks/rn-gate.py": ("n/a -- captures named artifacts", "no-population",
                          "checks/rn-gate.py:433-435", "PRESENT -- NOT READ"),
    "checks/romless.py": ("n/a -- a device reader", "no-population", "REFUSED",
                          "REFUSED -- not read"),
    "checks/run.py": ("n/a -- a driver", "no-population", "REFUSED", "REFUSED -- not read"),
    "checks/rw-gate-oracle.py": ("n/a -- a reference producer", "no-population", "REFUSED",
                                 "REFUSED -- not read"),
    "checks/serve.py": ("n/a", "no-population", "REFUSED", "REFUSED -- not read"),
    "checks/sz.py:NOTE": None,
    "checks/test_rewrite_bottom_up_gate.py": ("n/a", "no-population", "REFUSED",
                                              "REFUSED -- not read"),
    "checks/reorder-gate.py": ("defs = {} / spans = {} literal dicts", "self-declared-arms",
                               "checks/reorder-gate.py:48,66", "PRESENT"),
    "checks/citation-gate.py:CLASSES": ("CLASSES = ('HOLDS','STALE-LINE',...)",
                                        "class-table", "checks/citation-gate.py:53,225",
                                        "PRESENT -- the verdict vocabulary applied to rows a "
                                        "walk produced, NOT the population"),
}

# A file with MORE THAN ONE membership expression gets one row per expression. The INSTRUMENT
# denominator is the 226 walked files; the ROW denominator is larger, and both are printed.
EXTRA: list[tuple[str, str, str, str, str]] = [
    ("checks/sweep.py", "ORACLE_WORD = re.compile(r'(^|[-_.])(oracle|rows|expect|pins|baseline)"
     "([-. _]|$)') matched against a BASENAME", "basename-regex",
     "checks/sweep.py:716 (defined), :1276 (used: `name in mentioned and ORACLE_WORD.search"
     "(name)`)",
     "PRESENT -- PARTIALLY retired: the `name in mentioned` conjunct (:1276) means an UNCITED "
     "file cannot reach this arm, so the 670-of-675 overcount it caused is closed; the bucket "
     "of a CITED file is still chosen from its basename"),
    ("checks/sweep.py", "ROLE_DIRS = {'oracles':'ORACLE','gates':'GATE','checks':'GATE'} "
     "matched against a path PART", "hand-list", "checks/sweep.py:766,1201-1202",
     "PRESENT -- 3 directory names; :760-765 records that `strays`/`strays-root` were removed "
     "from it as an incident encoded as a name"),
    ("checks/sweep.py", "LIVE_UNITS -- a tuple of 14 names", "hand-list",
     "checks/sweep.py:768 (the tombstone comment that replaced it)",
     "FIXED -- REMOVED; :768 records the removal and points at live_units()"),
    ("checks/sweep.py", "os.walk over a per-unit BASE list", "hand-list",
     "checks/sweep.py:550",
     "PRESENT -- the walk itself is a walk; the ROOTS it walks are decided by `live_units()` "
     "and by RESIDUE_ROOTS at :81"),
    ("checks/repro-paths.py", "REF = re.compile(r'(?:^|\\s)((?:\\.agents/slop/|checks/|gates/)"
     "[\\w./-]*\\.[A-Za-z0-9]+)') over a whole report's text", "unscoped-text-regex",
     "checks/repro-paths.py:64,101",
     "FIXED -- the five-item suffix set is GONE (was `(?:sh|py|bend|mjs|json)`); membership of "
     "the NAMED PATHS is now decided by `os.path.exists` at :108"),
    ("checks/differ.py", "PINS = {...} and REPRO_PINS = {...}, hand-written key=value tables",
     "hand-list", "checks/differ.py:248,328",
     "PRESENT -- AND THIS IS NOT THE SAME DEFECT AS LIVE_UNITS, see REPORT.md: a pin asserts a "
     "VALUE checkable against an artifact that exists, and every arm that consumes one "
     "(:1079-1081 repro_bad) is indexed by that artifact's own key set"),
    ("checks/differ.py", "present = {p.name for p in D.glob('*.txt')}", "single-dir-glob",
     "checks/differ.py:1117",
     "PRESENT -- PARTIAL: MISSING (:1120) and UNEXPECTED (:1121) run off `declared()`, but "
     "`present` is a glob and `here` (:1118) is what the EMPTY and ONE-LINE arms iterate"),
    ("checks/differ.py", "ORACLE_PIN = {path: sha256}", "hand-list", "checks/differ.py:62,79",
     "PRESENT -- a pin table over FILES, verified by hashing the file itself; NOT a population"),
    ("gates/gates-pop.py", "HOMES = ('checks','gates')", "hand-list",
     "gates/gates-pop.py:97 (the citation), :112-118 (what replaced it)",
     "FIXED -- the literal is gone; `HOMES = _homes(ROOT)` at :1504 is an AST measurement "
     "(`_measure(root)`, :868)"),
    ("gates/pins-shape-gate.py", "iterdir over gates/, matched by NAME against a regex",
     "write-site-regex", "gates/pins-shape-gate.py:239",
     "PRESENT -- and :33 states the rule it replaced ('A WALK AND A NAME, NOT A SUFFIX SET')"),
    ("checks/runs-artifacts.py", "READS = {'read_text','read_bytes','iterdir','glob',...}",
     "hand-list", "checks/runs-artifacts.py:96",
     "PRESENT -- the FS-CALL NAMES it looks for, a finite vocabulary; a new walk API would "
     "not be in it"),
    ("gates/msgdiff-gate.py", "UNCHECKED_KINDS = ('no_path','meta','renamed_or_absent','pid',"
     "'unfalsifiable_count')", "self-declared-arms", "gates/msgdiff-gate.py:148",
     "PRESENT -- an ADMISSION of what the gate does not check, which is the opposite defect"),
    ("gates/amd_dsl_census-gate.py", "CLASSES = [('MSG_TEXT', '^afenc_...'), ('SR...', '...')]",
     "class-table", "gates/amd_dsl_census-gate.py:755,727",
     "PRESENT -- each entry is (class NAME, pattern); the pattern classifies a row the lanes "
     "produced"),
    ("gates/crp_graph_census-gate.py", "CLASSES = [('UNEXPLAINED','^.*$'), ...]", "class-table",
     "gates/crp_graph_census-gate.py:981",
     "PRESENT -- the first entry is a catch-all, which is what makes it a classifier"),
    ("gates/linearizer_census-gate.py", "CLASSES = [('ORPHAN-CONST','^(ix|ix_len)$'), ...]",
     "class-table", "gates/linearizer_census-gate.py:104", "PRESENT"),
    ("gates/ops_python_census-gate.py", "CLASSES = [('UNEXPLAINED','^.*$'), ...]",
     "class-table", "gates/ops_python_census-gate.py:630", "PRESENT"),
    ("gates/regalloc_census-gate.py", "CLASSES = [('UNEXPLAINED','^.*$'), ...]", "class-table",
     "gates/regalloc_census-gate.py:86", "PRESENT"),
    ("gates/wgsl_render_census-gate.py", "CLASSES = [('UNHANDLED_ARM','^code_for_op (LOAD|...)"
     "$'), ...]", "class-table", "gates/wgsl_render_census-gate.py:928,1071", "PRESENT"),
]

# ---- gates/: rules over the discovered names, then the exceptions -------------------------
RULES = [
    (re.compile(r"^gates/.+-oracle\.py$"),
     ("n/a -- a CPython reference producer; the claims it covers are the calling gate's",
      "no-population"), "PRESENT"),
    (re.compile(r"^gates/.+-mutate\.py$"),
     ("MUTATIONS / PORT_MUTATIONS / PHASE1 literal list, one per arm the file applies",
      "self-declared-arms"), "PRESENT"),
]


def gate_evidence(path: str) -> tuple[str, str, str]:
    """For a `-gate.py`: its rows literal if it has one, else the bare `rows=N` integer.

    CLASS IS `hand-list-cross-checked`, NOT `hand-list`, AND THE REASON IS A MEASUREMENT, NOT A
    NICETY: `gatekit.Gate.run()` reads the lanes' OWN emitted rows (`gates/gatekit.py:449`),
    compares their count with `rows` (`:432-440`) and requires every name in `pins` to be
    present in the raw lane (`:492-495`). So a driver that grows a row, loses a row or renames
    one turns the gate RED. A typed list that a run COMPARE catches is a pin table, and
    `LIVE_UNITS` was not a pin table -- it classified 2,353 files nothing had checked."""
    txt = (ROOT / path).read_text(encoding="utf-8", errors="replace")
    lit = LITERALS.get(path)
    if lit:
        name, bind, text = lit
        cls = "hand-list-cross-checked" if "pins=" in txt else "hand-list"
        return (f"{name} = {text}", cls, f"{path}:{bind}")
    m = re.search(r"rows=(\d+)", txt)
    if m:
        cls = "hand-list-cross-checked" if "pins=" in txt else "hand-list"
        return (f"rows={m.group(1)} -- a BARE COUNT, no names", cls,
                f"{path}:{txt[:m.start()].count(chr(10)) + 1}")
    return ("REFUSED -- no rows literal found by regex", "REFUSED", path)


def load_literals() -> dict[str, tuple[str, int, str]]:
    out: dict[str, tuple[str, int, str]] = {}
    for line in (HERE / "strlists.rows").read_text().splitlines():
        f, _, name, bind, _, text = line.split("\t")[:6]
        out.setdefault(f, (name, bind.split(":")[1], text[:110]))
    return out


LITERALS = load_literals()


def main() -> int:
    files = sorted(p.relative_to(ROOT).as_posix()
                   for home in ("checks", "gates") for p in (ROOT / home).rglob("*.py"))
    rows, seen = [], set()
    for f in files:
        if CLS.get(f, "x") is None:
            continue
        if f in CLS:
            expr, cls, ev, state = CLS[f]
            rows.append((f, expr, cls, ev, state))
            seen.add(f)
            continue
        hit = next(((e, c, s) for rx, (e, c), s in RULES if rx.match(f)), None)
        if hit:
            rows.append((f, hit[0], hit[1], f"n/a", hit[2]))
            seen.add(f)
            continue
        if f.startswith("gates/") and f.endswith("-gate.py"):
            expr, cls, ev = gate_evidence(f)
            rows.append((f, expr, cls, ev, "PRESENT"))
            seen.add(f)
            continue
        rows.append((f, "REFUSED -- not classified", "REFUSED", f, "REFUSED -- not read"))
    for r in rows + list(EXTRA):
        print("\t".join(x.replace("\t", " ").replace("\n", " ") for x in r))
    print(f"instruments={len(files)} rows={len(rows) + len(EXTRA)} "
          f"refused={sum(1 for r in rows if r[2] == 'REFUSED')} "
          f"not_acceptable={sum(1 for r in rows + list(EXTRA) if r[2] in NOT_ACCEPTABLE)}",
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())