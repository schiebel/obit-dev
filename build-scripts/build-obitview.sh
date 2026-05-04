#!/usr/bin/env bash
# build-scripts/build-obitview.sh
# Configure and build ObitSystem/ObitView (image display + ObitMess server)
#
# Motif is built from source by build-motif.sh and installed into
# tmp/motif-install/, so this script works identically on Linux and macOS.
# Run build-motif before this script (build-all handles ordering).

set -euo pipefail
source "$(dirname "$0")/common-env.sh"

COMP_DIR="$SRC_OBIT/ObitSystem/ObitView"
MOTIF_PREFIX="$BASE/tmp/motif-install"

# ---- preflight: verify Motif was built --------------------------------------
if [ ! -f "$MOTIF_PREFIX/include/Xm/Xm.h" ]; then
    echo "[build-obitview] ERROR: Motif headers not found at $MOTIF_PREFIX/include/Xm/Xm.h"
    echo "  Run 'pixi run build-motif' first, or use 'pixi run build-all'."
    exit 1
fi
echo "[build-obitview] Found Motif at $MOTIF_PREFIX ✓"

if [ ! -d "$COMP_DIR" ]; then
    echo "[build-obitview] ERROR: $COMP_DIR not found. Run clone-repo first."
    exit 1
fi

cd "$COMP_DIR"

if [ ! -f configure ] || [ configure.in -nt configure ] 2>/dev/null; then
    echo "[build-obitview] Running autoreconf"
    autoreconf -fiv || true
fi

# Point configure at both the conda X11 libraries and the from-source Motif
MOTIF_LDFLAGS="-L${MOTIF_PREFIX}/lib -Wl,-rpath,${MOTIF_PREFIX}/lib"

# ---- override dummy_xmlrpc headers -----------------------------------------
# Obit's Makefile always adds -I../dummy_xmlrpc to the include path.
# When real xmlrpc-c is installed, this causes conflicting declarations.
# Replace the dummy headers with wrappers that include the real ones.
DUMMY_DIR="$SRC_OBIT/ObitSystem/Obit/dummy_xmlrpc"
REAL_INC="$XMLRPC_PREFIX/include/xmlrpc-c"
echo "[build-obitview] Redirecting dummy_xmlrpc headers → real xmlrpc-c"
for header in xmlrpc.h xmlrpc_client.h; do
    if [ -f "$DUMMY_DIR/$header" ]; then
        cp "$DUMMY_DIR/$header" "$DUMMY_DIR/$header.orig" 2>/dev/null || true
        printf '/* redirected to real xmlrpc-c by build-obitview.sh */\n' > "$DUMMY_DIR/$header"
        printf "#include \"${REAL_INC}/base.h\"\n"         >> "$DUMMY_DIR/$header"
        printf "#include \"${REAL_INC}/client.h\"\n"       >> "$DUMMY_DIR/$header"
        printf "#include \"${REAL_INC}/server.h\"\n"       >> "$DUMMY_DIR/$header"
        printf "#include \"${REAL_INC}/server_abyss.h\"\n" >> "$DUMMY_DIR/$header"
        echo "  $header → real xmlrpc-c (absolute paths)"
    fi
done
# Also redirect dummy_xmlrpc/xmlrpc-c/ stubs — otherwise angle-bracket includes
# of <xmlrpc-c/client.h> resolve to the dummy stubs instead of the real headers.
mkdir -p "$DUMMY_DIR/xmlrpc-c"
for stub in base.h client.h server.h server_abyss.h util.h; do
    printf "/* stub redirected */\n#include \"${REAL_INC}/${stub}\"\n" \
        > "$DUMMY_DIR/xmlrpc-c/$stub"
done
echo "  xmlrpc-c/ stubs → real xmlrpc-c"
# ---- create flat xmlrpc shims -----------------------------------------------
# ObitView includes xmlrpc_client.h and xmlrpc.h as flat headers (not xmlrpc-c/).
# Create shims in the xmlrpc install include dir using absolute paths to avoid
# circular includes through dummy_xmlrpc/xmlrpc-c/.
echo "[build-obitview] Creating flat xmlrpc header shims"
REAL_INC="${XMLRPC_PREFIX}/include/xmlrpc-c"
for shim in xmlrpc_client.h xmlrpc.h xmlrpc_server.h xmlrpc_server_abyss.h; do
    target="${XMLRPC_PREFIX}/include/$shim"
    if true; then
        printf '/* shim: redirect to real xmlrpc-c headers */\n'         > "$target"
        printf "#include \"${REAL_INC}/base.h\"\n"                      >> "$target"
        printf "#include \"${REAL_INC}/client.h\"\n"                    >> "$target"
        printf "#include \"${REAL_INC}/server.h\"\n"                    >> "$target"
        printf "#include \"${REAL_INC}/server_abyss.h\"\n"              >> "$target"
        echo "  created $shim"
    fi
done

echo "[build-obitview] Configuring ObitView"
# conda's xorg headers are incomplete (missing XIMResetState in Xlib.h, etc.)
# Copy missing/incomplete headers from XQuartz to make conda X11 self-consistent.
if [ -d "/opt/X11/include/X11" ] && [ -d "${CONDA_PREFIX}/include/X11" ]; then
    # These files are either missing from conda or have incomplete definitions
    for f in Xosdefs.h Xos.h Xos_r.h Xfuncproto.h Xlib.h XlibInt.h Xlibint.h; do
        src="/opt/X11/include/X11/$f"
        dst="${CONDA_PREFIX}/include/X11/$f"
        if [ -f "$src" ]; then
            # Copy if missing or if XQuartz version is newer/different
            if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
                echo "[build-obitview] Patching $f from XQuartz → conda"
                cp "$src" "$dst"
            fi
        fi
    done
fi
# ---- create xmlrpc-c-config shim -------------------------------------------
# ObitView's configure calls xmlrpc-c-config to find xmlrpc-c flags.
# Since we built xmlrpc-c manually, create a shim on PATH.
SHIM_BIN="${BASE}/tmp/shims"
mkdir -p "$SHIM_BIN"
cat > "$SHIM_BIN/xmlrpc-c-config" << SHIMEOF
#!/bin/sh
PREFIX="${XMLRPC_PREFIX}"
case "\$1" in
    --version)   echo "1.51.0" ;;
    --features)  echo "abyss-server" ;;
    --libs)      echo "-L\${PREFIX}/lib -lxmlrpc -lxmlrpc_util" ;;
    --ldadd)     echo "-L\${PREFIX}/lib -lxmlrpc_server_abyss -lxmlrpc_server -lxmlrpc_client -lxmlrpc -lxmlrpc_util -lxmlrpc_abyss -lxmlrpc_xmlparse -lxmlrpc_xmltok" ;;
    --cflags)    echo "-I\${PREFIX}/include" ;;
    *)           echo "-I\${PREFIX}/include" ;;
esac
SHIMEOF
chmod +x "$SHIM_BIN/xmlrpc-c-config"
export PATH="$SHIM_BIN:$PATH"
echo "[build-obitview] Created xmlrpc-c-config shim at $SHIM_BIN"

# Build CPPFLAGS fresh to ensure Motif include is definitely present
MOTIF_CPPFLAGS="-I/opt/X11/include -I${MOTIF_PREFIX}/include -I${CONDA_PREFIX}/include"
export CPPFLAGS="$MOTIF_CPPFLAGS"
export LDFLAGS="-L${XMLRPC_PREFIX}/lib -L${MOTIF_PREFIX}/lib -L${OBIT_HOME}/lib -L${CONDA_PREFIX}/lib -L/opt/X11/lib $RPATH_FLAG"
export MOTIF_CFLAGS="-I${MOTIF_PREFIX}/include"
export MOTIF_LIBS="-L${MOTIF_PREFIX}/lib -lXm"
echo "[build-obitview] CPPFLAGS=$CPPFLAGS"
echo "[build-obitview] Verify Xm.h exists: $(ls ${MOTIF_PREFIX}/include/Xm/Xm.h 2>/dev/null || echo MISSING)"

./configure \
    --cache-file=/dev/null \
    --exec-prefix="$SRC_OBIT" \
    --with-obit="$OBIT_HOME" \
    "$WITH_CFITSIO" \
    "$WITH_FFTW" \
    "$WITH_GSL" \
    "$WITH_GLIB" \
    "$WITH_CURL" \
    "$WITH_XMLRPC" \
    "$WITH_ZLIB" \
    --with-motif="$MOTIF_PREFIX" \
    --with-plplot \
    --x-includes="${CONDA_PREFIX}/include" \
    --x-libraries="${CONDA_PREFIX}/lib" \
    OBIT="$OBIT_HOME" \
    OBITINSTALL="$SRC_OBIT" \
    CPPFLAGS="$CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_PATH="$PKG_CONFIG_PATH"

echo "[build-obitview] Building ObitView (NPROC=$NPROC)"
# Use -j1 for the Obit library rebuild step to avoid race conditions where
# .o files get mv'd before ar can find them.
# Use -I (not -isystem) for xmlrpc so it takes priority over dummy_xmlrpc.
make -j1 \
    CFLAGS="-std=gnu89 -I${XMLRPC_PREFIX}/include -I/opt/X11/include -I${MOTIF_PREFIX}/include -Wno-deprecated-declarations -Wno-error -Wno-implicit-function-declaration -Wno-incompatible-pointer-types" \
    clean all
make install

echo "[build-obitview] Done."
