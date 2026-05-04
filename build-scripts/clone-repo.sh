#!/usr/bin/env bash
# build-scripts/clone-repo.sh
# Clone the Obit GitHub repository into src/Obit

set -euo pipefail

REPO_URL="${OBIT_REPO_URL:-https://github.com/bill-cotton/Obit}"
SRC_DIR="$(pwd)/src/Obit"

if [ -d "$SRC_DIR/.git" ]; then
    echo "[clone-repo] src/Obit already exists — pulling latest commits"
    git -C "$SRC_DIR" pull --ff-only
else
    echo "[clone-repo] Cloning $REPO_URL → $SRC_DIR"
    mkdir -p "$(pwd)/src"
    git clone "$REPO_URL" "$SRC_DIR"
fi

echo "[clone-repo] Done."
