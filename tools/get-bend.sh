#!/bin/sh
# Fetch the pinned Bend 2 compiler into vendor/. It is a toolchain dependency
# (the Rust/C rewrite target), not part of the port, so it is gitignored.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REF=${BEND_REF:-2.0.34}
[ -d "$ROOT/vendor/bend" ] && { echo "vendor/bend already present"; exit 0; }
mkdir -p "$ROOT/vendor"
git clone --depth 30 --branch "$REF" https://github.com/HigherOrderCO/Bend.git "$ROOT/vendor/bend"
echo "vendored bend $REF into vendor/bend"
