#!/usr/bin/env python3
"""Q2 -- THE PLANT, and the evidence it is a plant.

A plant that reports AGREE is not a plant. This probe therefore does three things BEFORE it
reports anything, because each has been this project's failure mode:

  1. it asserts the planted graph is NOT byte-identical to the clean one (`cmp` on the two
     canonical files is the same check `graphcmp-run.sh` step 02 does, and step 02's version
     was measured to pass vacuously over two EMPTY files once);
  2. it asserts the two differ in a NAMED field, not merely in a digest -- a digest that moves
     is a count, and a count cannot say WHERE it landed;
  3. it prints the node count on both sides, because a plant that changed one field of a
     32-node graph and a plant that rebuilt the graph are different plants and the digest does
     not tell them apart.

THE PLANT ITSELF: `--plant dsexpand` drops the second EXPAND's shape source from the
`(3,4,4)` seed down to a CONST, so the seed's shape changes from `(l0:3,l0:4,l0:4)` to
`(l0:4,l0:4)` and the reshape that follows must disagree. It is the RIGHT plant for `bw`
because `EXPAND` is the op this graph exists to reach: a plant that did not touch the new op
would be a plant about the graph's furniture.

NO PLANT OF THE BEND SIDE, and that is the file's own measured rule, not a gap: `--plant-side`
was removed in round one because planting the bend side means writing DAG rewrites in Bend
against a graph the port builds node for node -- a second implementation of the tree.
"""
import os
import sys

os.environ.setdefault("DEV", "NULL")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import graphcmp as G                                        # noqa: E402


def named_fields(clean, dirty, side="py"):
  """Which of the eight fields DIFFER, by NAME, node by node -- so the answer is a list of
  field names and not a digest."""
  c, _, _ = G.build(clean, side)
  d, _, _ = G.build(dirty, side)
  out = {}
  for nid, a in sorted(c.items(), key=lambda kv: int(kv[0])):
    b = d.get(nid)
    if b is None:
      out.setdefault("MISSING", []).append(f"{a.op}#{nid}")
      continue
    for f in G.FIELDS:
      if getattr(a, f) != getattr(b, f):
        out.setdefault(f, []).append(f"{a.op}#{nid}")
  for nid, b in sorted(d.items(), key=lambda kv: int(kv[0])):
    if nid not in c:
      out.setdefault("ADDED", []).append(f"{b.op}#{nid}")
  return out


def main() -> int:
  G.load_tinygrad()
  G.COMM = G.commutative()

  clean = G.emit_py("bw", None)
  print("q2_clean_nodes=%d rows=%d" % (len(G.base("bw").toposort()), len(clean)))

  # ---- the four PRECONDITIONS, in this order, and each one can fail ----------------
  grown = G.emit_py("bw", "dsexpand")
  print("q2_plant_nodes=%d" % len(grown))
  if clean == grown:
    print("q2_FAIL the plant is a NO-OP: the planted stream is byte-identical to the clean "
          "one, so anything downstream of it would be reading a control")
    return 1
  print("q2_precond_1_stream_differs=OK")

  fs = named_fields(clean, grown)
  if not fs:
    print("q2_FAIL the streams differ but NO FIELD is named, which would mean the difference "
          "is in a column the differ does not compare (R1 `id`)")
    return 1
  print("q2_precond_2_a_field_is_named=OK  fields=%s" % sorted(fs))
  for f, ns in sorted(fs.items()):
    print("q2_field_%-7s n=%-3d nodes=%s" % (f, len(ns), ",".join(ns)))

  # ---- AND the differ actually NAMES it, which is the only claim that matters --------
  rc, txt = G.report(clean, grown, "dsexpand", "clean", "dsexpand")
  verds = [ln for ln in txt.splitlines() if ln.startswith(("# VERDICT", "# DENOMINATOR",
                                                           "# SHARED", "# RESIDUALS"))]
  for v in verds:
    print("q2_diff %s" % v)
  named = G.field_named(txt, "shape")
  print("q2_diff_names_shape=%s rc=%d" % (named, rc))
  if rc == 0:
    print("q2_FAIL the differ reports AGREE on a planted graph -- the plant is not reaching "
          "the comparison")
    return 1
  if not named:
    print("q2_FAIL the differ disagrees but does not NAME the shape field, so the report says "
          "something differs and not what")
    return 1

  # ---- the ledger on both sides of the plant, so a residual cannot hide in the delta ----
  for tag, rows in (("clean", clean), ("dsexpand", grown)):
    print("q2_ledger_%-8s %s" % (tag, " ".join("%s=%d" % kv for kv in sorted(G.ledger(rows).items()))))

  # ============================ THE PAIRED DISARM ==============================
  # A red with no paired disarm proves nothing about WHERE it landed: it only proves the
  # differ is not the identity. The disarm is the same edit with the meaning removed -- same
  # target node, same op, same node count, same field-records -- and it MUST read AGREE.
  # Three controls in this project were found disarmed, so this is asserted, not assumed.
  dis = G.emit_py("bw", "disarm")
  print("")
  print("q2_disarm_nodes=%d rows=%d" % (len(G.base("bw").toposort()), len(dis)))
  if dis != clean:
    print("q2_FAIL the DISARM moved the stream, so the plant's red is not attributable to "
          "the value change -- the rebuild itself is changing something.  %d of %d rows differ"
          % (sum(1 for a, b in zip(clean, dis) if a != b), len(clean)))
    return 1
  print("q2_disarm_stream_identical=OK  (the rebuild reached the same ucache nodes)")

  rcd, txtd = G.report(clean, dis, "disarm", "clean", "disarm")
  for v in [ln for ln in txtd.splitlines() if ln.startswith(("# VERDICT", "# DENOMINATOR", "# SHARED"))]:
    print("q2_disarm %s" % v)
  if rcd != 0:
    print("q2_FAIL the DISARM reports DISAGREE -- it is not a null, so the plant's red says "
          "nothing about which edit caused it")
    return 1
  print("q2_disarm_verdict=AGREE  (so the plant's DISAGREE is attributable to the VALUE "
        "change and not to the rebuild)")

  # ---- AND THE PAIR, SIDE BY SIDE, with the denominators that make them comparable ----
  print("")
  print("q2_PAIR  clean-vs-dsexpand DISAGREE rc=%d names_shape=%s   "
        "clean-vs-disarm AGREE rc=%d   same graph, same %d nodes, same %d field-records"
        % (rc, named, rcd, len(clean), len(clean) * len(G.FIELDS)))
  return 0


if __name__ == "__main__":
  sys.exit(main())