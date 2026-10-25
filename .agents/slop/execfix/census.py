#!/usr/bin/env python3
"""THE EXECUTOR CENSUS, RUN AGAINST ONE COMPILED EXECUTOR.

    .venv/bin/python .agents/slop/execfix/census.py <executor> <out.rows>

IT IS THE `gates/ops_python_exec-gate.py` LANE `bd`, REWRITTEN HERE BECAUSE MY
BRIEF FORBIDS RUNNING `gates/*` OTHER THAN `gates/ops_bend_exec-e2e.py`:

    "NEVER run ... `gates/*` other than `gates/ops_bend_exec-e2e.py`"

SO THE POPULATION IS THE TREE'S OWN FIXTURE FILE, READ IN PLACE AND NEVER
WRITTEN -- `gates/ops_python_exec-fixtures.rows`, 153 records, each a verbatim
`PACKET.in` under an `@ <name> <gx> <gy> <gz> <vals...>` header. THE FILE IS THE
TREE'S RECORD OF THE POPULATION; NOTHING HERE INVENTS ONE.

THE ROWS ARE THE GATE'S OWN SPELLING (`gates/ops_python_exec-gate.py:196`):

    <name>.b<i>=<hex>        one per buffer line of PACKET.out
    <name>=REFUSED-<rc>      the executor died 1 with "refused the packet"

ONE EXECUTOR PROCESS AT A TIME. The brief says one bend process at a time, and
the gate's own comment says the executor's peak RSS is 606420992 bytes -- so
`--jobs 6` (3.6 GB) is not what this machine is allowed to do.

WHY IT IS USEFUL WITHOUT THE ORACLE LANE: THE ROWS ARE COMPARED BETWEEN TWO
EXECUTORS (THE HEAD ONE AND THE FIXED ONE), AND A ROW WHOSE BYTES ARE
UNCHANGED IS A ROW WHOSE VERDICT IS UNCHANGED -- WHETHER IT MATCHED CPYTHON OR
NOT. ONLY THE ROWS THAT MOVE NEED AN ORACLE, AND THOSE ARE ADJUDICATED ONE BY
ONE AGAINST CPython's OWN `tinygrad/runtime/ops_python.py` (the `PYTHON` device).
"""
import pathlib, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
FIXTURES = ROOT / "gates" / "ops_python_exec-fixtures.rows"


def fixtures():
    """`[(name, argv, packet_text)]`. THE FILE IS READ, NEVER WRITTEN."""
    recs, cur = [], None
    for ln in FIXTURES.read_text().splitlines():
        if ln.startswith("@ "):
            head = ln.split()[1:]
            cur = [head[0], tuple(int(x) for x in head[1:]), []]
            recs.append(cur)
        elif cur is not None and ln.strip():
            cur[2].append(ln)
    return [(n, a, "\n".join(p) + "\n") for n, a, p in recs]


def run_one(exe, td, name, argv, packet):
    """ONE fixture, ONE PROCESS, ITS OWN DIRECTORY.

    THE OWN DIRECTORY IS THE PORT'S CONTRACT: `Prog.write.out`
    (`tinybendygrad/runtime/ops_python.bend`) finds the LAST `/` of the packet's
    path and writes `PACKET.out` beside it, so a shared directory has every
    fixture racing for one file.
    """
    d = td / name
    d.mkdir(parents=True, exist_ok=True)
    (d / "PACKET.in").write_text(packet)
    r = subprocess.run([str(exe), str(d / "PACKET.in"), *[str(v) for v in argv]],
                       capture_output=True, text=True)
    if r.returncode != 0:
        if "refused the packet" in (r.stderr + r.stdout):
            return [f"{name}=REFUSED-{r.returncode}"]
        return [f"{name}=DIED-{r.returncode}-{(r.stderr or r.stdout).strip()[-40:]}"]
    out = d / "PACKET.out"
    if not out.exists():
        return [f"{name}=NO-PACKET.out"]
    rows = []
    for i, ln in enumerate(out.read_text().splitlines()):
        f = ln.split()
        rows.append(f"{name}.b{i}={f[1] if len(f) > 1 else ''}")
    return rows


def main():
    exe = pathlib.Path(sys.argv[1]).resolve()
    dest = pathlib.Path(sys.argv[2])
    fx = fixtures()
    rows = []
    with tempfile.TemporaryDirectory(prefix="execfix-census-") as td:
        td = pathlib.Path(td)
        for i, (n, a, p) in enumerate(fx):
            rows.extend(run_one(exe, td, n, a, p))
            if (i + 1) % 25 == 0:
                print(f"# {i + 1}/{len(fx)} fixtures", file=sys.stderr)
    dest.write_text("\n".join(sorted(rows)) + "\n")
    print(f"# {len(fx)} fixtures, {len(rows)} rows -> {dest}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
