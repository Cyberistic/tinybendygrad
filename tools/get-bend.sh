#!/bin/sh
# Fetch the pinned Bend 2 compiler into references/. It is a toolchain
# dependency, not part of the port, so it is gitignored (see README.md).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REF=${BEND_REF:-v2.0.39}
# THE PIN IS CHECKED, NOT DECLARED. It was `exit 0` on an existing clone, so `BEND_REF`
# could be any string and nothing would notice -- MEASURED 2026-10-14: it said `v2.0.34`
# while the clone sat on a MOVING `main` tip at `018751270e80`. A PIN THAT CANNOT BE
# VIOLATED IS NOT A PIN. Now it answers REFUSED (3) with both versions named.
if [ -d "$ROOT/references/bend/.git" ]; then
  got=$(git -C "$ROOT/references/bend" describe --tags --exact-match HEAD 2>/dev/null || echo UNPINNED-BRANCH)
  if [ "$got" != "$REF" ]; then
    echo "bend REFUSED: references/bend is at $got, the pin says $REF" >&2
    echo "  fix: git -C references/bend fetch --depth 1 origin tag $REF && git -C references/bend checkout $REF" >&2
    exit 3
  fi
  echo "references/bend already at $REF"; exit 0
fi
mkdir -p "$ROOT/references"
git clone --depth 30 --branch "$REF" https://github.com/HigherOrderCO/Bend.git "$ROOT/references/bend"
echo "bend $REF -> references/bend"
