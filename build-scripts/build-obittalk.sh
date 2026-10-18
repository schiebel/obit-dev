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

# ---------------------------------------------------------------------------
# Python 2→3 compatibility: ObitTalk.py uses `input` as both a variable name
# and the built-in function on the same line, which fails in Python 3.
# e.g.  input = input("Please enter your AIPS user ID number: ")
# After that assignment `input` is a str, so any subsequent input() call
# raises TypeError: 'str' object is not callable.
# Fix: rename the local variable to `user_input` throughout ObitTalk.py and
# ObitTalk3.py (they are generated from the same template).
# ---------------------------------------------------------------------------
echo "[build-obittalk] Patching ObitTalk.py / ObitTalk3.py: rename 'input' variable → 'user_input'"
for pyfile in \
    "$COMP_DIR/bin/ObitTalk.py" \
    "$COMP_DIR/bin/ObitTalk3.py"; do
    if [ -f "$pyfile" ]; then
        # Replace  `input = input(`  →  `user_input = input(`
        # Replace subsequent bare  `input`  used as the received string
        # (but NOT calls like  input(  which are the built-in).
        # Strategy:
        #   1. Turn  `input = input(`  into  `user_input = input(`
        #   2. Where `input` appears as a bare value (not followed by `(`)
        #      replace it with `user_input`.  We use a two-pass approach.
        # Pass 1: rename the assignment  `input = input(`  →  `user_input = input(`
        sed -i.bak \
            -e 's/\binput = input(/user_input = input(/g' \
            "$pyfile"
        # Pass 2: replace bare `input` used as a *value* (not the built-in call).
        # We must NOT touch occurrences followed by `(` (those are the built-in).
        # POSIX sed has no negative lookahead; instead, protect `input(` with a
        # placeholder that cannot appear in real Python, fix bare `input`, restore.
        sed -i \
            -e 's/\binput(/__INPUTBUILTIN__(/g' \
            -e 's/\binput\b/user_input/g' \
            -e 's/__INPUTBUILTIN__/input/g' \
            "$pyfile"
        echo "[build-obittalk]   Patched: $pyfile"
    fi
done

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
