"""Summarise the per-file BEND sweep and classify each completed-file failure against the CPU control.

Every number carries its denominator. A file whose verdict is FAULTHANDLER-TIMEOUT / KILLED-BY-SWEEP is
NOT counted as passed/failed: it measured nothing, and folding its zeros into a total would be the
zero-denominator lie doctrine 2 names. Those files' collected counts are reported separately.
"""
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
BEND = HERE / "bend"
CPU = (HERE / "null-cpu.out").read_text()

rows = [ln.split("\t") for ln in (HERE / "sweep-bend.tsv").read_text().splitlines()[1:]]
COLS = ["file", "verdict", "wall_s", "collected", "passed", "failed", "errored", "skipped", "xfailed"]
recs = [dict(zip(COLS, r)) for r in rows]
for rec in recs:
    for k in ("collected", "passed", "failed", "errored", "skipped", "xfailed"):
        rec[k] = int(rec[k])

RAN = {"COMPLETED", "COMPLETED-RED"}
NOT_RAN = {"FAULTHANDLER-TIMEOUT", "KILLED-BY-SWEEP"}
ran, noran = [r for r in recs if r["verdict"] in RAN], [r for r in recs if r["verdict"] in NOT_RAN]


def total(rs, key):
    return sum(r[key] for r in rs)


print(f"files total            {len(recs)}")
print(f"  ran to completion    {len(ran)}   (COMPLETED {sum(r['verdict']=='COMPLETED' for r in ran)}, "
      f"COMPLETED-RED {sum(r['verdict']=='COMPLETED-RED' for r in ran)})")
print(f"  measured nothing     {len(noran)}  (FAULTHANDLER-TIMEOUT "
      f"{sum(r['verdict']=='FAULTHANDLER-TIMEOUT' for r in noran)}, "
      f"KILLED-BY-SWEEP {sum(r['verdict']=='KILLED-BY-SWEEP' for r in noran)})")
print()
print("COMPLETED FILES ONLY (the real BEND denominator):")
for key in ("collected", "passed", "failed", "errored", "skipped", "xfailed"):
    print(f"  {key:10s} {total(ran, key)}    /{total(ran,'collected')} collected")
print()
print("UNMEASURED FILES (collected counts, no verdict):")
for r in noran:
    print(f"  {r['file']:45s} collected={r['collected']:4d}  {r['verdict']}")
print(f"  TOTAL unmeasured collected = {total(noran,'collected')}")
print()
print(f"ALL {len(recs)} FILES collected (denominator upper bound) = {total(recs,'collected')}")

# --- failure classification: BEND failed ids vs CPU failed ids ---
failed_hdr = re.compile(r"^_{5,} (.*?) _{5,}$", re.M)


def bend_failed_ids(rec):
    out = (BEND / f"{pathlib.Path(rec['file']).stem}.out").read_text()
    ids = set(failed_hdr.findall(out))
    return {re.sub(r"\s*\(.*\)$", "", i).strip() for i in ids}


cpu_failed = set(failed_hdr.findall(CPU))
cpu_failed = {re.sub(r"\s*\(.*\)$", "", i).strip() for i in cpu_failed}

print()
print("FAILURES PER COMPLETED-RED FILE (id -> whether CPU also failed it):")
device_dep, device_indep = [], []
for r in ran:
    if r["failed"] == 0 and r["errored"] == 0:
        continue
    ids = bend_failed_ids(r)
    for i in sorted(ids):
        (device_indep if i in cpu_failed else device_dep).append((r["file"], i))
    print(f"  {r['file']:45s} failed={r['failed']} errored={r['errored']}")
    for i in sorted(ids):
        print(f"      {'CPU-ALSO' if i in cpu_failed else 'BEND-ONLY'}  {i}")

print()
print(f"BEND failures ALSO on CPU (device-independent): {len(device_indep)}")
print(f"BEND failures NOT on CPU (device-dependent / port): {len(device_dep)}")
for f, i in device_dep:
    print(f"    {f}::{i}")
