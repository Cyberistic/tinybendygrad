#!/usr/bin/env python3
"""gates/target-census-gate.py -- THE PORT MUST DECLARE `Target` ONCE, AND THE ONCE MUST BE UPSTREAM'S.

    .venv/bin/python gates/target-census-gate.py
    .venv/bin/python gates/target-census-gate.py --plant

WHAT THIS GATE IS FOR. Upstream has ONE `Target` (`tinygrad/helpers.py:198`), and
upstream's `uop/ops.py:13` and `runtime/ops_python.py:9` both IMPORT it from
there. The port had TWO: `runtime/ops_python.bend` declared one (the record, its
accessors and the DEV parser) and `uop/ops.bend` declared another (the record and
`Target.of()`). They had the same five fields and they were DIFFERENT TYPES, so a
parsed `Target` could not go into a `ProgramInfo`, and the two could drift apart
with nothing in the tree noticing. A type is not a name: the port's contract is
behaviour, but two records with the same field names are two records.

THE POPULATION IS DISCOVERED, NOT NAMED. `os.walk` over `tinybendygrad/` plus
`endswith(".bend")` -- never `glob` (which returns `[]` when `.bend` files are on
disk, and did). Every `type Target is Data:` in the port is a member of this
gate's population, wherever it is, and the gate names them.

THE ORDER IS THE ARM THAT MATTERS, and it is a SILENT one. Two records with the
same five field NAMES in a different order are not interchangeable: a positional
construction puts the values in the wrong slots and a positional pattern compares
the wrong pairs, and neither complains. So the field list is checked as an ORDERED
list, not as a set, and the order-sensitive USES (`Target{` to build, `case
Target{` to destructure) are checked to be in the canonical file or qualified with
the canonical's alias.

EXITS are `gatekit`'s. PASS 0, FAIL 1, REFUSED 3, SKIP 4, DEAD 5.
"""
from __future__ import annotations

import os
import re
import sys
import tempfile
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402

PORT_REL = "tinybendygrad"
CANONICAL = "tinybendygrad/helpers.bend"
# upstream's record, in upstream's order. `interface` is spelled `iface` here and
# NOTHING ELSE differs -- that one rename is the whole difference between
# upstream's dataclass and the port's.
UPSTREAM_FIELDS = ("device", "renderer", "arch", "iface", "indices")
SKIP_DIRS = {".git", ".venv", "__pycache__", "node_modules", "references"}

DECL = re.compile(r"^type\s+Target\s+is\s+Data:\s*$")
CTOR = re.compile(r"^\s*Target\{(?P<fields>[^}]*)\}\s*$")
PROGINFO = re.compile(r"^type\s+ProgramInfo\s+is\s+Data:\s*$")
IMPORT_HELPERS = re.compile(r"^import\s+\.{1,2}/?.*helpers\.bend\s+as\s+(?P<alias>[A-Za-z_][A-Za-z0-9_]*)\s*$")

# The plant's SYNTHETIC control port. Two files, one record, one consumer.
CANON_HELPERS = ("import Base\n\n"
                  "type Target is Data:\n"
                  "  @ORDER@\n")
CANON_OPS = ("import Base\n"
             "import ./../helpers.bend as H\n\n"
             "type ProgramInfo is Data:\n"
             "  ProgramInfo{global_size: List<&2, U32>, target: @TF@}\n\n"
             "def p(+pi: ProgramInfo) -> @TF@:\n"
             "  match pi:\n"
             "    case ProgramInfo{global_size, target}: target\n")


def walk_bend(root: Path) -> list[Path]:
  """Every `.bend` file under `root`. `os.walk` + `endswith`, never `glob`."""
  found: list[Path] = []
  for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
    for name in sorted(filenames):
      if name.endswith(".bend"):
        found.append(Path(dirpath) / name)
  return sorted(found)


def field_names(ctor: str) -> list[str]:
  """The field names of a record constructor, IN ORDER."""
  out = []
  for part in ctor.split(","):
    part = part.strip()
    if not part:
      continue
    out.append(part.split(":", 1)[0].strip())
  return out


def helpers_alias(body: list[str]) -> str | None:
  """The alias this file imports `helpers.bend` under, or None."""
  for line in body:
    m = IMPORT_HELPERS.match(line.strip())
    if m:
      return m.group("alias")
  return None


def survey(root: Path) -> dict:
  """Everything this gate measures, discovered by walking the port."""
  port = root / PORT_REL
  records: list[dict] = []
  program_infos: list[dict] = []
  order_sensitive: list[dict] = []
  for path in walk_bend(port):
    rel = str(path.relative_to(root))
    body = path.read_text(encoding="utf-8", errors="replace").splitlines()
    alias = helpers_alias(body)
    for i, line in enumerate(body):
      if DECL.match(line):
        ctor = ""
        for j in range(i + 1, min(i + 4, len(body))):
          m = CTOR.match(body[j])
          if m:
            ctor = m.group("fields")
            break
        records.append({"rel": rel, "at": i + 1, "fields": field_names(ctor), "ctor": ctor})
      if PROGINFO.match(line):
        ctor = ""
        for j in range(i + 1, min(i + 4, len(body))):
          m = re.match(r"^\s*ProgramInfo\{(?P<fields>[^}]*)\}\s*$", body[j])
          if m:
            ctor = m.group("fields")
            break
        program_infos.append({"rel": rel, "at": i + 1, "fields": field_names(ctor), "ctor": ctor,
                              "alias": alias})
    for i, line in enumerate(body):
      stripped = line.strip()
      if stripped.startswith("#"):
        continue
      if re.search(r"(?<![\w.])Target\{", stripped) or re.search(r"case\s+Target\{", stripped):
        order_sensitive.append({"rel": rel, "at": i + 1, "line": stripped, "alias": alias})
  return {"records": records, "program_infos": program_infos, "order_sensitive": order_sensitive}


def claims(sv: dict) -> list[tuple[str, bool, str]]:
  """The four claims, each with a verdict and the line that says why."""
  out: list[tuple[str, bool, str]] = []
  recs = sv["records"]

  # C1 -- EXACTLY ONE.
  out.append(("C1-ONE-RECORD", len(recs) == 1,
              f"{len(recs)} `type Target is Data:` declaration(s): "
              + ", ".join(f"{r['rel']}:{r['at']}" for r in recs)))

  # C2 -- THE ONE IS UPSTREAM'S HOME.
  where = [r["rel"] for r in recs]
  out.append(("C2-CANONICAL-HOME", where == [CANONICAL],
              f"declared in {where or ['<none>']}, want [{CANONICAL!r}]"))

  # C3 -- THE FIELDS, IN ORDER. Upstream's order, with `interface` as `iface`.
  for r in recs:
    out.append((f"C3-FIELDS[{r['rel']}]", tuple(r["fields"]) == UPSTREAM_FIELDS,
                f"{r['rel']}:{r['at']} fields={r['fields']} want={list(UPSTREAM_FIELDS)}"))

  # C4 -- `ProgramInfo.target` IS THE CANONICAL RECORD, qualified with the
  # alias this file imports `helpers.bend` under. A BARE `Target` means the
  # file declares its own, and that is the nominal-identity defect.
  for pi in sv["program_infos"]:
    rel = pi["rel"]
    alias = pi.get("alias")
    target_field = ""
    for f, spec in zip(pi["fields"], [x.strip() for x in pi["ctor"].split(",")]):
      if f == "target":
        target_field = spec.split(":", 1)[1].strip() if ":" in spec else ""
    want = f"{alias}.Target" if alias else "?"
    out.append((f"C4-PROGRAMINFO[{rel}]", target_field == want and alias is not None,
                f"{rel}:{pi['at']} ProgramInfo.target={target_field!r} want={want!r}"))

  # C5 -- THE ORDER-SENSITIVE USES ARE IN THE CANONICAL FILE OR QUALIFIED.
  # A construction or a positional pattern on a record declared SOMEWHERE ELSE
  # is where a wrong field order would bite silently. ONE claim per FILE: the
  # lines are the evidence, not the claim.
  by_file: dict[str, list[dict]] = {}
  for use in sv["order_sensitive"]:
    if use["rel"] == CANONICAL:
      continue
    by_file.setdefault(use["rel"], []).append(use)
  for rel, uses in sorted(by_file.items()):
    alias = uses[0]["alias"]
    ok = alias is not None and all(
      re.search(rf"(?<![\w.]){re.escape(alias)}\.Target\{{", u["line"]) for u in uses)
    where = ", ".join(f"{u['at']}" for u in uses[:6]) + ("..." if len(uses) > 6 else "")
    out.append((f"C5-ORDER-USE[{rel}]", ok,
                f"{rel}: {len(uses)} order-sensitive use(s) at {where} -- "
                f"not the canonical record, and not qualified with {alias!r}"))
  return out


def verdict_of_claims(cs: list[tuple[str, bool, str]]) -> int:
  return PASS if all(ok for _n, ok, _w in cs) else FAIL


def emit(sv: dict, cs: list[tuple[str, bool, str]], n_bend: int) -> None:
  print(f"target-census POPULATION os.walk {PORT_REL}/ endswith .bend = {n_bend}")
  print(f"target-census CANONICAL {CANONICAL} (upstream tinygrad/helpers.py:198)")
  print(f"target-census UPSTREAM-FIELDS {list(UPSTREAM_FIELDS)} (upstream's order; "
        f"`interface` is spelled `iface`)")
  for name, ok, why in cs:
    print(f"target-census CLAIM {name} {'PASS' if ok else 'FAIL'} -- {why}")
  bad = [n for n, ok, _w in cs if not ok]
  if bad:
    print("target-census REMEDY the record is declared once, in "
          f"{CANONICAL}, with the fields in upstream's order; every consumer spells it "
          "`<alias>.Target` where `<alias>` is that file's `helpers.bend` alias.")


def plant() -> int:
  """Five arms, each a mutation of a copy of the port, each caught.

  A1 A SECOND `Target` RECORD -- the defect itself: two records, same five
     fields, DIFFERENT types, and a parsed target that cannot go into a
     `ProgramInfo`.
  A2 THE FIELD ORDER -- the same five names in a different order. Not
     interchangeable, and silently wrong: a construction puts the values in the
     wrong slots and a pattern compares the wrong pairs.
  A3 A FIELD DROPPED -- a conversion that loses one.
  A4 A FIELD RENAMED -- `interface` where the port spells `iface`, so the port
     and upstream's field names drift apart.
  A5 THE NOMINAL ARM -- `ProgramInfo.target` spelled with a BARE `Target`, which
     is a record declared somewhere else: structurally identical, nominally
     not.
  """
  try:
    return _plant()
  except Exception:
    print("target-census PLANT FAILED: a crash is not a pass", file=sys.stderr)
    traceback.print_exc()
    return FAIL


def _plant() -> int:
  bad: list[str] = []
  with tempfile.TemporaryDirectory(prefix="target-census-plant-") as raw:
    td = Path(raw)
    tree = td / "port"
    (tree / PORT_REL / "uop").mkdir(parents=True)
    # A SYNTHETIC, KNOWN-GOOD PORT. The plant does not measure the real tree's
    # state -- the real tree may be in the defective state this gate exists to
    # name, and a control that is red for that reason cannot tell a mutation
    # from the defect. The control is written here so it is green by
    # construction, and every arm is read against it.
    ORDER = "Target{device: String, renderer: String, arch: String, iface: String, indices: String}"
    BAD_ORDER = "Target{device: String, renderer: String, iface: String, arch: String, indices: String}"
    DROPPED = "Target{device: String, renderer: String, arch: String, iface: String}"
    RENAMED = "Target{device: String, renderer: String, arch: String, interface: String, indices: String}"
    (tree / PORT_REL / "helpers.bend").write_text(CANON_HELPERS.replace("@ORDER@", ORDER), encoding="utf-8")
    (tree / PORT_REL / "uop" / "ops.bend").write_text(CANON_OPS.replace("@TF@", "H.Target"), encoding="utf-8")

    control = claims(survey(tree))
    n_bad = sum(1 for _n, ok, _w in control if not ok)
    print(f"target-census PLANT control claims={len(control)} failing={n_bad}")
    if n_bad:
      print("target-census PLANT control is not clean, so a mutation cannot be read: "
            + "; ".join(f"{n}: {w}" for n, ok, w in control if not ok), file=sys.stderr)
      return FAIL

    def write_pair(helpers: str, ops: str) -> None:
      (tree / PORT_REL / "helpers.bend").write_text(helpers, encoding="utf-8")
      (tree / PORT_REL / "uop" / "ops.bend").write_text(ops, encoding="utf-8")

    CANON = f"{PORT_REL}/helpers.bend"
    OPS = f"{PORT_REL}/uop/ops.bend"
    # A6 -- the record declared ONCE, but in the WRONG FILE. Upstream's home is
    # `helpers.py:198` and the port's mirror of that file is `helpers.bend`, so a
    # single record in `uop/ops.bend` is upstream's `uop/ops.py` DEFINING what
    # upstream's `uop/ops.py` IMPORTS. One record is not the claim; ONE record
    # IN THE RIGHT PLACE is.
    WRONG_HOME_HELPERS = "import Base\n"
    WRONG_HOME_OPS = ("import Base\n\ntype Target is Data:\n  " + ORDER + "\n\n"
                      "type ProgramInfo is Data:\n"
                      "  ProgramInfo{global_size: List<&2, U32>, target: Target}\n\n"
                      "def p(+pi: ProgramInfo) -> Target:\n"
                      "  match pi:\n"
                      "    case ProgramInfo{global_size, target}: target\n")

    arms = [
      ("A1-SECOND-RECORD", "C1-ONE-RECORD",
       lambda: (tree / PORT_REL / "extra_target.bend").write_text(
         "import Base\n\ntype Target is Data:\n  " + ORDER + "\n", encoding="utf-8"),
       lambda: (tree / PORT_REL / "extra_target.bend").unlink()),
      ("A2-FIELD-ORDER", "C3-FIELDS",
       lambda: write_pair(CANON_HELPERS.replace("@ORDER@", BAD_ORDER),
                          CANON_OPS.replace("@TF@", "H.Target")),
       lambda: write_pair(CANON_HELPERS.replace("@ORDER@", ORDER),
                          CANON_OPS.replace("@TF@", "H.Target"))),
      ("A3-FIELD-DROPPED", "C3-FIELDS",
       lambda: write_pair(CANON_HELPERS.replace("@ORDER@", DROPPED),
                          CANON_OPS.replace("@TF@", "H.Target")),
       lambda: write_pair(CANON_HELPERS.replace("@ORDER@", ORDER),
                          CANON_OPS.replace("@TF@", "H.Target"))),
      ("A4-FIELD-RENAMED", "C3-FIELDS",
       lambda: write_pair(CANON_HELPERS.replace("@ORDER@", RENAMED),
                          CANON_OPS.replace("@TF@", "H.Target")),
       lambda: write_pair(CANON_HELPERS.replace("@ORDER@", ORDER),
                          CANON_OPS.replace("@TF@", "H.Target"))),
      ("A5-NOMINAL-IDENTITY", "C4-PROGRAMINFO",
       lambda: write_pair(CANON_HELPERS.replace("@ORDER@", ORDER),
                          CANON_OPS.replace("@TF@", "Target")),
       lambda: write_pair(CANON_HELPERS.replace("@ORDER@", ORDER),
                          CANON_OPS.replace("@TF@", "H.Target"))),
      ("A6-RECORD-IN-THE-WRONG-FILE", "C2-CANONICAL-HOME",
       lambda: write_pair(WRONG_HOME_HELPERS, WRONG_HOME_OPS),
       lambda: write_pair(CANON_HELPERS.replace("@ORDER@", ORDER),
                          CANON_OPS.replace("@TF@", "H.Target"))),
    ]

    for name, claim, plant_it, unplant in arms:
      plant_it()
      cs = claims(survey(tree))
      hit = [(n, w) for n, ok, w in cs if not ok]
      print(f"target-census PLANT {name} -> {[n for n, _w in hit]}")
      if not any(n.startswith(claim) for n, _w in hit):
        bad.append(f"{name}: the gate did not go red (expected a {claim} failure)")
      unplant()
      cs2 = claims(survey(tree))
      if any(not ok for _n, ok, _w in cs2):
        bad.append(f"{name}: the gate did not come back green")

  if bad:
    print("target-census PLANT FAILED: " + "; ".join(bad), file=sys.stderr)
    return FAIL
  print("target-census PLANT OK: a second record, a different field order, a dropped field, "
        "a renamed field and a bare `Target` in `ProgramInfo.target` are each caught, "
        "and the control comes back green")
  return PASS


def main(argv: list[str]) -> int:
  if "--plant" in argv:
    return plant()
  port = ROOT / PORT_REL
  if not port.is_dir():
    print(f"target-census REFUSED: port tree {port} is absent", file=sys.stderr)
    return REFUSED
  bend = walk_bend(port)
  if not bend:
    print("target-census DEAD: the port walk found no .bend file", file=sys.stderr)
    return DEAD
  sv = survey(ROOT)
  if not sv["records"]:
    print("target-census DEAD: the walk found no `type Target is Data:` at all", file=sys.stderr)
    return DEAD
  cs = claims(sv)
  emit(sv, cs, len(bend))
  code = verdict_of_claims(cs)
  n_bad = sum(1 for _n, ok, _w in cs if not ok)
  print(f"target-census VERDICT {VERDICT[code]} -- {n_bad} of {len(cs)} claims failed")
  return code


if __name__ == "__main__":
  sys.exit(main(sys.argv[1:]))
