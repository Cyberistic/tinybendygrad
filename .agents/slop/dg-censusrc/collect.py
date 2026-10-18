"""STATIC diagnosis of the `census-rc=rc=1` pin. Reads differ.py's AST and the census
artifact; runs no oracle, no bend, no graphcmp, no gate. Emits state.rows (TAB-separated)."""
import ast, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = pathlib.Path(__file__).resolve().parent

differ = (ROOT / "checks/differ.py").read_text().splitlines()
artifact = (ROOT / "runs/graphcmp/D/D0-coverage-census.txt").read_text().splitlines()
summary = dict(
    ln.split("=", 1)
    for ln in (ROOT / "runs/graphcmp/D/D0-run-summary.txt").read_text().splitlines()
    if "=" in ln
)

pins = {}
for node in ast.parse("\n".join(differ)).body:
    if isinstance(node, ast.Assign) and any(
        isinstance(t, ast.Name) and t.id == "PINS" for t in node.targets
    ):
        pins = {k.value: ast.literal_eval(v) for k, v in zip(node.value.keys, node.value.values)}
        break

# ONLY the lines `for b in bad: print("#   " + b)` emitted, and that loop runs IMMEDIATELY after
# the SELFCHECK line. Counting every `#   ` line in the file instead swept up 17 lines of PROSE
# the oracle prints as its own commentary (`:43-56`, DEFECT 20's paragraph), which is how the
# first version of this script reported 18 `bad` entries against a true 1. The denominator is
# `bad`, and `bad` is only what the print loop emits.
sc = next(i for i, ln in enumerate(artifact) if ln.startswith("# ORACLE SELFCHECK"))
tail = artifact[sc + 1:]
bad_rows = [ln for ln in tail if ln.startswith("#   ")]
bad_rows = bad_rows[: len(tail) - sum(1 for ln in tail if not ln.startswith("#"))]
last = artifact[-1]
red = sorted(k for k, v in pins.items() if summary.get(k, "ABSENT") != pins[k])

R = [
 ("census-rc.pinned", pins["census-rc"], "checks/differ.py:269",
  "PINS[\"census-rc\"] in the 17-key table"),
 ("census-rc.recorded", summary["census-rc"], "runs/graphcmp/D/D0-run-summary.txt:19",
  "FAIL: recorded != pinned"),
 ("census-rc.origin", "oracle returncode", "checks/differ.py:458,461",
  "subprocess.run(...).returncode written as rc=N; NOT a fallback"),
 ("census-rc.reader", "last_line()", "checks/differ.py:979,1267-1268",
  "census-rc is the artifact's LAST line; no default, no ABSENT arm"),
 ("census-rc.fallback", "NONE", "checks/differ.py:979",
  "an unstamped empty artifact would record census-rc= (empty), not rc=1"),
 ("capture.default", "stamp_rc=False", "checks/differ.py:451",
  "the parameter defaults OFF; the census opts in explicitly"),
 ("capture.census-call", "stamp_rc=True", "checks/differ.py:907",
  "the census DOES stamp, so even a crash records rc="),
 ("capture.other-calls", "stamp_rc omitted (x2)", "checks/differ.py:910,914",
  "D8b-cpython-dbg1-reachability and D0-ops-probe would record NO rc= on a crash"),
 ("priorclaim.684", "one_line() body", "checks/differ.py:684",
  "REFUTED as a citation: :684 is the one_line newline count, not a capture call"),
 ("priorclaim.691", "blank line in cmd_run", "checks/differ.py:691",
  "REFUTED as a citation: :691 is blank; the census call is :907"),
 ("priorclaim.substance", "true for 2 of 3 lanes", "checks/differ.py:910,914",
  "a crashed unstamped lane records no rc=; NOT true of the census"),
 ("oracle.exit", "return 0 if not bad else 1", "graphcmp-oracle.py:534,538",
  "sys.exit(main()); rc=1 means selfcheck FAIL, not a harness code"),
 ("artifact.lastline", last, "runs/graphcmp/D/D0-coverage-census.txt:73",
  "the stamp written by capture(), byte-identical to the oracle's own exit"),
 ("artifact.selfcheck", "# ORACLE SELFCHECK: FAIL", "runs/graphcmp/D/D0-coverage-census.txt:71",
  "printed at graphcmp-oracle.py:531 before the bad list"),
 ("artifact.bad.count", str(len(bad_rows)), "runs/graphcmp/D/D0-coverage-census.txt:72-73",
  "1 bad entry, of the 1 line the print loop emitted after SELFCHECK; prose excluded"),
 ("artifact.bad.who", "loop device mismatch", "runs/graphcmp/D/D0-coverage-census.txt:72",
  "py ['N','sCPU'] against bend ['sCPU']; N is ATOMS[\"none\"], an ABSENCE"),
 ("artifact.traceback", "NONE", "runs/graphcmp/D/D0-coverage-census.txt",
  "no Traceback and no IndexError; the lane completed and asserted"),
 ("artifact.errsidecar", "ABSENT", "runs/graphcmp/D/D0-coverage-census.txt.err",
  "capture() merges stderr INTO the artifact (stdout=f, stderr=f): no .err to read"),
 ("crossread.samefile", "both pins, one file", "checks/differ.py:978,979",
  "oracle-selfcheck and census-rc BOTH read D0-coverage-census.txt"),
 ("oracle-selfcheck.pinned", pins["oracle-selfcheck"], "checks/differ.py:293",
  "same table, adjacent concern, same artifact"),
 ("oracle-selfcheck.recorded", summary["oracle-selfcheck"], "runs/graphcmp/D/D0-run-summary.txt:18",
  "FAIL: same oracle process, same artifact, one self-check"),
 ("other.selfcheck", summary["selfcheck"], "runs/graphcmp/D/D0-run-summary.txt:15",
  "tinygrad's own D0-selfcheck.txt is OK: a DIFFERENT oracle"),
 ("refused.graph", "loop", "runs/graphcmp/D/D1-graph-loop.txt",
  "rc=2 PARTIAL FIXTURE 25 of 52 nodes; a REFUSED, not a disagreement"),
 ("refused.count", summary["graphs-refused"], "runs/graphcmp/D/D0-run-summary.txt:5",
  "1 graph answered nothing; differ counts it apart from expect-moved"),
 ("graphs-agree.recorded", summary["graphs-agree"], "runs/graphcmp/D/D0-run-summary.txt:6",
  f"FAIL: expected {pins['graphs-agree']}; 34 minus the 1 refused"),
 ("byte-identical.recorded", summary["byte-identical"], "runs/graphcmp/D/D0-run-summary.txt:8",
  f"FAIL: expected {pins['byte-identical']}; same cause as graphs-agree"),
 ("pins.denominator", f"{len(red)} FAIL of {len(pins)}", "checks/differ.py:248",
  "red = " + ", ".join(red)),
 ("staleness.artifact", "2026-10-18T21:22:13Z", "stat runs/graphcmp/D/D0-coverage-census.txt",
  "written by the PRE-fix oracle"),
 ("staleness.fix", "2026-10-18T21:28:06Z", "stat .agents/slop/graphcmp-oracle.py",
  "NODEV landed 5m53s AFTER the artifact; in HEAD (9f0164b6e, 21:30:30)"),
 ("fix.commit", "9f0164b6e", "git log -S'NODEV = frozenset'",
  "message: 'failed on both pins'; states both pins are ONE cause"),
 ("fix.measured", "SELFCHECK OK, rc=0", "commit 9f0164b6e message",
  "oracle re-run standalone 2026-10-18T18:29:16Z per the commit; full run NOT re-taken"),
 ("substrate.dep", "SUBSTRATE_INPUTS[5]", "checks/differ.py:1174-1177",
  "graphcmp-oracle.py IS a substrate input; commit 9f0164b6e says [4] (off by one)"),
 ("verify.instrument", "gates/census-dev-gate.py", "gates/census-dev-gate.py",
  "asserts device_verdict with NO bend; commit claims 8 of 8"),
 ("verify.plant", "checks/graphcmp-census-audit.py", "checks/graphcmp-census-audit.py",
  "PLANT 2 and 3 still drive SELFCHECK FAIL rc=1 through the fatal branch"),
]

(OUT / "state.rows").write_text(
    "".join("\t".join(c.replace("\t", " ").replace("\n", " ") for c in row) + "\n" for row in R)
)
print(f"wrote {len(R)} rows; pins {len(red)} FAIL of {len(pins)}; bad entries {len(bad_rows)}")
print(f"artifact last line: {last!r}")