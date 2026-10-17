"""Decisive check for the remaining UNADJUDICATED rows: does the instrument CREATE the file?
A window of +-400 chars around any mention of the basename, searched for a write/create verb.
Admitted as a heuristic, and its misses are named in the report -- but every UNADJUDICATED row
is own_dir absent, so a plant verdict here cannot manufacture an external finding."""
import pathlib, re
D = pathlib.Path(__file__).resolve().parent
ROOT = ROOTP = pathlib.Path(__file__).resolve().parents[3]
WRITE = re.compile(r"write_text|write_bytes|unlink|mkdir|mkdtemp|TemporaryDirectory|"
                   r"shutil\.copy|shutil\.move|\.write\(|open\([^)]*[\"'][wax]|copy2|copytree|"
                   r"touch|rm -f|cat >|cp |mv ")
miss, hit = [], 0
for line in (D / "sites.rows").read_text().splitlines():
    if not line.startswith(("#", "instrument")):
        pass
parts = [l.split("\t") for l in (D / "sites.rows").read_text().splitlines() if not l.startswith("#")]
for p in parts:
    if len(p) < 6 or p[5] != "UNADJUDICATED":
        continue
    inst, tgt = p[0], p[1]
    src = (ROOT / inst).read_text(errors="replace")
    base = tgt.rsplit("/", 1)[-1]
    ok = False
    for m in re.finditer(re.escape(base), src):
        w = src[max(0, m.start() - 400): m.end() + 400]
        if WRITE.search(w):
            ok = True
            break
    if ok:
        hit += 1
    else:
        miss.append((inst, tgt))
print(f"unadjudicated_rows_with_a_write_verb_near_the_name\t{hit}")
print(f"unadjudicated_rows_without\t{len(miss)}")
for i, t in miss:
    print(f"  MISS\t{i}\t{t}")
