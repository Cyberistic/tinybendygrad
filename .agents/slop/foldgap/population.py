#!/usr/bin/env python
"""Doctrine 1: the population is DISCOVERED, not listed.

Reads the `Op` enum's own declaration in ops.bend and the arms of `dt_shape`
in fold.bend, and asks how many enum members share each answer. Emits a
`.rows` table. Never touches disk state beyond its own output.
"""
import re
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[3]
OPS = ROOT / "tinybendygrad/uop/ops.bend"
FOLD = ROOT / "tinybendygrad/uop/fold.bend"


def enum_members(path):
    text = path.read_text().splitlines()
    start = next(i for i, l in enumerate(text) if l.strip() == "type Op is Data:")
    members, seen = [], False
    for line in text[start + 1:]:
        m = re.match(r"^\s+(Ops[A-Z0-9_]+)\{\}\s*$", line)
        if m:
            members.append(m.group(1))
            seen = True
        elif seen and line.strip() and not line.strip().startswith("#"):
            break
    return members


def dt_shape_arms(path):
    """Every `case O.<M>{}:` inside `def dt_shape`, body on the same line."""
    text = path.read_text().splitlines()
    start = next(i for i, l in enumerate(text) if l.startswith("def dt_shape("))
    arms = {}
    for line in text[start:]:
        if line.startswith("def ") and not line.startswith("def dt_shape("):
            break
        m = re.match(r"^\s+case O\.(Ops[A-Z0-9_]+)\{\}\s*:\s*(.*)$", line)
        if m:
            arms[m.group(1)] = m.group(2).strip()
    return arms


def classify(body):
    if body == "late()":
        return "late"
    if body == "None{}":
        return "bare-none"
    return "derived"


def main():
    members = enum_members(OPS)
    arms = dt_shape_arms(FOLD)
    out = ROOT / ".agents/slop/foldgap/population.rows"
    rows = ["member\tarm\tclass"]
    counts = {"late": 0, "bare-none": 0, "derived": 0, "absent": 0}
    for m in members:
        if m not in arms:
            cls = "absent"
        else:
            cls = classify(arms[m])
        counts[cls] += 1
        rows.append(f"{m}\t{arms.get(m, '<no arm>')}\t{cls}")
    # arms naming a member the enum does not declare = a dispatch/edit defect
    stray = sorted(set(arms) - set(members))
    rows.append("")
    rows.append("# denominator (doctrine 1: enum declaration is the population)")
    rows.append(f"# enum members\t{len(members)}")
    for cls in ("derived", "late", "bare-none", "absent"):
        rows.append(f"# {cls}\t{counts[cls]}")
    rows.append(f"# stray arms (not in enum)\t{len(stray)}")
    for s in stray:
        rows.append(f"#   stray\t{s}")
    out.write_text("\n".join(rows) + "\n")
    print(f"wrote {out} ({len(members)} members)")
    print(counts)
    if stray:
        print("STRAY:", stray)


if __name__ == "__main__":
    main()
