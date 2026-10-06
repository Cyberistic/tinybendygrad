#!/bin/sh
# Fetch the pinned Bend 2 compiler into references/. It is a toolchain
# dependency, not part of the port, so it is gitignored (see README.md).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REF=${BEND_REF:-v2.0.34}
[ -d "$ROOT/references/bend" ] && { echo "references/bend already present"; exit 0; }
mkdir -p "$ROOT/references"
git clone --depth 30 --branch "$REF" https://github.com/HigherOrderCO/Bend.git "$ROOT/references/bend"
echo "bend $REF -> references/bend"
