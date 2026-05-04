#!/usr/bin/env bash
# build-scripts/build-obit.sh
# Configure and build ObitSystem/Obit (the core C library + tasks)

set -euo pipefail
source "$(dirname "$0")/common-env.sh"

COMP_DIR="$SRC_OBIT/ObitSystem/Obit"

if [ ! -d "$COMP_DIR" ]; then
    echo "[build-obit] ERROR: $COMP_DIR not found. Run clone-repo first."
    exit 1
fi

cd "$COMP_DIR"

# Run autoreconf only if configure is missing or stale
if [ ! -f configure ] || [ configure.in -nt configure ] 2>/dev/null; then
    echo "[build-obit] Running autoreconf"
    autoreconf -fiv || true   # some older m4 macros warn; continue
fi

# ---- override dummy_xmlrpc headers -----------------------------------------
DUMMY_DIR="$SRC_OBIT/ObitSystem/Obit/dummy_xmlrpc"
REAL_INC="$XMLRPC_PREFIX/include/xmlrpc-c"
echo "[build-obit] Redirecting dummy_xmlrpc headers → real xmlrpc-c"
for header in xmlrpc.h xmlrpc_client.h; do
    if [ -f "$DUMMY_DIR/$header" ]; then
        cp "$DUMMY_DIR/$header" "$DUMMY_DIR/$header.orig" 2>/dev/null || true
        printf '/* redirected to real xmlrpc-c by build-obit.sh */\n' > "$DUMMY_DIR/$header"
        printf "#include \"${REAL_INC}/base.h\"\n"         >> "$DUMMY_DIR/$header"
        printf "#include \"${REAL_INC}/client.h\"\n"       >> "$DUMMY_DIR/$header"
        printf "#include \"${REAL_INC}/server.h\"\n"       >> "$DUMMY_DIR/$header"
        printf "#include \"${REAL_INC}/server_abyss.h\"\n" >> "$DUMMY_DIR/$header"
        echo "  $header → real xmlrpc-c (absolute paths)"
    fi
done

mkdir -p "$DUMMY_DIR/xmlrpc-c"
for stub in base.h client.h server.h server_abyss.h util.h; do
    printf "/* stub redirected */\n#include \"${REAL_INC}/${stub}\"\n" \
        > "$DUMMY_DIR/xmlrpc-c/$stub"
done
echo "  xmlrpc-c/ stubs → real xmlrpc-c"

# ---- patch ObitPlot.c -------------------------------------------------------
# Modern PLplot removed plwid() in favour of plwidth(). Obit's source still
# calls plwid() with a comment acknowledging the rename. Patch it.
OBITPLOT="$SRC_OBIT/ObitSystem/Obit/src/ObitPlot.c"
if grep -q 'plwid' "$OBITPLOT" 2>/dev/null; then
    echo "[build-obit] Patching ObitPlot.c: plwid → plwidth"
    sed -i.bak 's/plwid (/plwidth (/g' "$OBITPLOT"
fi

echo "[build-obit] Configuring Obit core"
./configure \
    --exec-prefix="$SRC_OBIT" \
    --with-obit="$OBIT_HOME" \
    "$WITH_CFITSIO" \
    "$WITH_FFTW" \
    "$WITH_GSL" \
    "$WITH_GLIB" \
    "$WITH_CURL" \
    "$WITH_XMLRPC" \
    "$WITH_ZLIB" \
    "$WITH_PYTHON" \
    "$WITH_BOOST" \
    --without-plplot \
    --without-wvr \
    OBIT="$OBIT_HOME" \
    OBITINSTALL="$SRC_OBIT" \
    LDFLAGS="$LDFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    CFLAGS="$CFLAGS" \
    PKG_CONFIG_PATH="$PKG_CONFIG_PATH"

echo "[build-obit] Building Obit core (NPROC=$NPROC)"
OBIT_CFLAGS="-std=gnu89 -fPIC -I${XMLRPC_PREFIX}/include -Wno-deprecated-declarations -Wno-error -Wno-implicit-function-declaration -Wno-incompatible-pointer-types"

# Step 1: build src and lib only (skip python which needs libObit.so)
make -j1 CFLAGS="$OBIT_CFLAGS" clean
make -j1 CFLAGS="$OBIT_CFLAGS" -C src
make -j1 CFLAGS="$OBIT_CFLAGS" -C lib

# Step 2: create libObit.so from the static archive so Python SWIG can link
OBIT_LIB="$OBIT_HOME/lib"
if true; then
    echo "[build-obit] Building libObit.so for Python bindings"
    TMPDIR_OBJ="$(mktemp -d)"
    # Extract Obit objects
    mkdir -p "$TMPDIR_OBJ/obit"
    cd "$TMPDIR_OBJ/obit"
    ar x "$OBIT_LIB/libObit.a"
    # Extract each xmlrpc-c static lib into its own subdir to avoid name collisions
    I=0
    for xlib in "${XMLRPC_PREFIX}/lib"/libxmlrpc*.a; do
        I=$((I+1))
        mkdir -p "$TMPDIR_OBJ/xr${I}"
        cd "$TMPDIR_OBJ/xr${I}"
        ar x "$xlib"
    done
    # Link everything into libObit.so.
    # libObit.a unconditionally references PLplot symbols (ObitPlot.c),
    # so we must link -lplplot even when built --without-plplot.
    cd "$TMPDIR_OBJ"
    gcc -shared -o "$OBIT_LIB/libObit.so" obit/*.o xr*/*.o \
        -L"${CONDA_PREFIX}/lib" \
        -lplplot \
        ${RPATH_FLAG} \
        -Wl,-undefined,dynamic_lookup
    cd "$OBIT_HOME"
    rm -rf "$TMPDIR_OBJ"
    echo "[build-obit] Created $OBIT_LIB/libObit.so"
fi

# Step 3: now build python (has libObit.so available)
make -j1 CFLAGS="$OBIT_CFLAGS" -C python

echo "[build-obit] Done."
