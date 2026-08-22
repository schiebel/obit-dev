#!/usr/bin/env bash
# build-scripts/build-obittalk.sh
# Configure and build ObitSystem/ObitTalk (Python interface to Obit)

set -euo pipefail
source "$(dirname "$0")/common-env.sh"

COMP_DIR="$SRC_OBIT/ObitSystem/ObitTalk"
OPT_PREFIX="$SRC_OBIT/opt"   # mirrors the original --prefix=$BASE/opt convention

if [ ! -d "$COMP_DIR" ]; then
    echo "[build-obittalk] ERROR: $COMP_DIR not found. Run clone-repo first."
    exit 1
fi

cd "$COMP_DIR"

# Clean any stale config artefacts
rm -f config.status config.log

if [ ! -f configure ] || [ configure.in -nt configure ] 2>/dev/null; then
    echo "[build-obittalk] Running autoreconf"
    autoreconf -fiv || true
fi

echo "[build-obittalk] Configuring ObitTalk"
./configure \
    --prefix="$OPT_PREFIX" \
    --exec-prefix="$SRC_OBIT" \
    --with-obit="$OBIT_HOME" \
    OBIT="$OBIT_HOME" \
    ADDPATH="${CONDA_PREFIX}/lib" \
    LDFLAGS="$LDFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    PKG_CONFIG_PATH="$PKG_CONFIG_PATH"

echo "[build-obittalk] Building ObitTalk (NPROC=$NPROC)"
# ObitTalk's bin/Makefile generates ObitTalk/ObitTalk3/ObitTalkServer via
# parallel sed+mv sequences that race against each other. Use -j1 for safety.
# Skip the doc target — it requires LaTeX which is not a pixi dependency.
make -j1 clean
make -j1 -C bin all install
make -j1 -C python all install
make -j1 -C test all

echo "[build-obittalk] Done."
echo "  Python modules are in: $OPT_PREFIX/share/obittalk/python"
echo "  Source setup.sh (written by write-setup task) before running ObitTalk."
