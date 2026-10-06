#!/bin/sh
# THE ORACLE'S TWO GUARDS, VERBATIM, AS AN ARBITRABLE HARNESS.
#
#     usage: sh oracle-probe.sh <dir> <healthy|artefacts_ok|verdict>
#
# `healthy()` and `artefacts_ok()` are extracted BY LINE RANGE from
# `.agents/slop/diffpy/oracle-repro.sh` (:60-87 and :102-119), so this measures the FROZEN CODE
# rather than a paraphrase of it. The ONLY edit is `runs/graphcmp/D` -> `$1`, because the point
# of the experiment is to vary the population those two guards are pointed at.
#
# Digests of the two extracted regions as read (MEASURED, re-check with diff-extract.md):
#   oracle-repro.sh:60-87   4abb7c62e77df36b27c16eda56dbb928ed86b34a702dd8b6d6a11253415b088d
#   oracle-repro.sh:102-119 8baf3310f87824e141d4e17c3de748e8771c6bbdd4f62307231bdfe06f8533df
D=$1
sed -n '60,87p' .agents/slop/diffpy/oracle-repro.sh \
  | sed "s|runs/graphcmp/D|$D|g; s|s=runs/graphcmp/D/D0-run-summary.txt|s=$D/D0-run-summary.txt|" > "$D.probe.sh"
sed -n '102,119p' .agents/slop/diffpy/oracle-repro.sh \
  | sed "s|runs/graphcmp/D|$D|g" >> "$D.probe.sh"
. "$D.probe.sh"
case $2 in
  healthy)      healthy; echo "rc=$?" ;;
  artefacts_ok) artefacts_ok ;;
  verdict)      # the ONE LINE `clean_run` prints, which is what a reader actually sees
    if healthy; then
      bad=$(artefacts_ok)
      if [ -z "$bad" ]; then echo "healthy run, and every artefact has a body"
      else echo "summary healthy but $(echo "$bad" | wc -l | tr -d ' ') malformed artefact(s)"; fi
    else echo "summary was NOT healthy -- waiting"; fi ;;
esac
rm -f "$D.probe.sh"