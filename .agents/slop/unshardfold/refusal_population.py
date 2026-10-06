#!/usr/bin/env python
"""Doctrine 1: the population is DISCOVERED, not listed.

Reads the `Op` enum's own declaration (ops.bend) and `dt_shape`'s arms
(fold.bend), then asks, for EACH member, whether its arm can REACH the refusal
`dt_of(dt, None)` -- i.e. whether the arm's body can answer `None{}`.

Three classes, decided by reading the called def, not the arm's spelling:
  answer   -- ends in `dt_of(dt, Some{...})` (a real shape, never None)
  refuses  -- reaches `dt_of(dt, <Maybe>)` where the Maybe can be None, or `None{}`
  late     -- `late()`: honest void + no shape (upstream's own answer)

Emits a `.rows` table. Never touches disk beyond its own output.
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[3]
OPS = ROOT / "tinybendygrad/uop/ops.bend"
FOLD = ROOT / "tinybendygrad/uop/fold.bend"
OUT = ROOT / ".agents/slop/unshardfold/refusal-population.rows"


def enum_members(path):
    lines = path.read_text().splitlines()
    start = next(i for i, l in enumerate(lines) if l.strip() == "type Op is Data:")
    members, seen = [], False
    for line in lines[start + 1:]:
        m = re.match(r"^\s+(Ops[A-Z0-9_]+)\{\}\s*$", line)
        if m:
            members.append(m.group(1))
            seen = True
        elif seen and line.strip() and not line.strip().startswith("#"):
            break
    return members


def dt_shape_arms(path):
    lines = path.read_text().splitlines()
    start = next(i for i, l in enumerate(lines) if l.startswith("def dt_shape("))
    arms = {}
    for line in lines[start:]:
        if line.startswith("def ") and not line.startswith("def dt_shape("):
            break
        m = re.match(r"^\s+case O\.(Ops[A-Z0-9_]+)\{\}\s*:\s*(.*)$", line)
        if m:
            arms[m.group(1)] = m.group(2).strip()
    return arms


def def_bodies(path):
    """Every top-level `def name`'s body text, keyed by name."""
    lines = path.read_text().splitlines()
    out, cur, buf = {}, None, []
    for line in lines:
        m = re.match(r"^def ([A-Za-z0-9_.]+)\(", line)
        if m:
            if cur is not None:
                out[cur] = "\n".join(buf)
            cur, buf = m.group(1), []
        elif cur is not None:
            buf.append(line)
    if cur is not None:
        out[cur] = "\n".join(buf)
    return out


def base_callee(arm_body):
    """The first identifier of an arm body like `thru0(ss)` -> `thru0`."""
    m = re.match(r"^([A-Za-z0-9_.]+)\s*\(", arm_body)
    return m.group(1) if m else None


def reaches_refusal(body, bodies, seen):
    """Does this def body reach `dt_of(dt, <non-Some>)` or a bare `None{}`?"""
    if body.strip() == "None{}":
        return True
    # a literal `dt_of(<x>, None{})` or `dt_of_if(..., <m>)` is the refusal.
    if re.search(r"dt_of\([^,]+,\s*None\{\}\)", body):
        return True
    # `dt_of(dt, src_shape(...))`, `bcast_shape(...)`, `marg(...)`, `stage_shape(...)`,
    # `both(...)`, `Maybe.map(...)` -- any second arg that is NOT `Some{`.
    for m in re.finditer(r"dt_of\([^,]+,\s*(.+)\)", body):
        arg = m.group(1)
        if not arg.startswith("Some{"):
            return True
    # a transitive call into another refusing def
    for m in re.finditer(r"([A-Za-z0-9_.]+)\s*\(", body):
        callee = m.group(1)
        if callee in seen or callee not in bodies:
            continue
        if reaches_refusal(bodies[callee], bodies, seen | {callee}):
            return True
    return False


# The arms whose refusal is their OWN missing mechanism (they refuse even when every
# src is answered with a dtype+shape). ADMITTED HERE AS A LEDGER, per doctrine 1's
# rule (c): the list is the four rules whose body reads a construct that can answer
# `None` for a reason OTHER than "a src was deferred":
#   UNSHARD  -> bare `None{}`; the shape needs `int(r.vmax+1)` (`_min_max`)
#   STAGE    -> `stage_shape`; the prepend needs `int(r.vmax+1)` (`_min_max`)
#   RESHAPE  -> `reshape_ds.of` passes `marg(ar, i)` straight into the answer; a
#               `sym_dim`-refused marg is `None` (foldgap's "symbolic-marg RESHAPE")
#   EXPAND   -> `both(marg(ar, i), src_shape(0, ss))`; same `marg` direct
# PAD/SHRINK/PERMUTE/FLIP also call `marg`, but through `Pairs.ok`/`Perm.ok` guards
# that match upstream's raises, so their refusal is a CHECK and not a missing rule.
OWN_WALL_OPS = {"OpsUNSHARD", "OpsSTAGE", "OpsRESHAPE", "OpsEXPAND"}


def main():
    members = enum_members(OPS)
    arms = dt_shape_arms(FOLD)
    bodies = def_bodies(FOLD)
    rows = ["member\tarm\tclass"]
    counts = {"answer": 0, "cascade-refuse": 0, "own-wall-refuse": 0,
              "late": 0, "absent": 0}
    own, cascade = [], []
    for mb in members:
        arm = arms.get(mb)
        if arm is None:
            cls, arm = "absent", "<no arm>"
        elif arm == "late()":
            cls = "late"
        else:
            callee = base_callee(arm)
            body = bodies.get(callee, "") if callee else arm
            if arm == "None{}" or mb in OWN_WALL_OPS:
                cls = "own-wall-refuse"
            elif callee in bodies and reaches_refusal(bodies[callee], bodies, {callee}):
                cls = "cascade-refuse"
            else:
                cls = "answer"
        counts[cls] += 1
        if cls == "own-wall-refuse":
            own.append(mb)
        elif cls == "cascade-refuse":
            cascade.append(mb)
        if cls == "refuses":
            refusing.append(mb)
        rows.append(f"{mb}\t{arm}\t{cls}")
    rows += ["", "# denominator (enum declaration is the population)",
             f"# enum members\t{len(members)}"]
    for cls in ("answer", "cascade-refuse", "own-wall-refuse", "late", "absent"):
        rows.append(f"# {cls}\t{counts[cls]}")
    rows.append("# own-wall (standalone) refusing members\t" + ",".join(own))
    rows.append("# cascade refusing members\t" + ",".join(cascade))
    OUT.write_text("\n".join(rows) + "\n")
    print("wrote", OUT, "members", len(members))
    print(counts)
    print("OWN-WALL:", ",".join(own))
    print("CASCADE:", len(cascade))


if __name__ == "__main__":
    main()
