#!/usr/bin/env bash
# build-scripts/build-xmlrpc.sh
#
# Builds xmlrpc-c from the tarball bundled in Obit's other/tarballs/ tree.
# Applies three source patches needed to build the 2008-vintage source with
# a modern compiler, then builds only the library subdirectories that Obit
# actually needs (skipping examples and tools which have additional problems).

set -euo pipefail

BASE="$(pwd)"
SRC_OBIT="$BASE/src/Obit"
TARBALLS_DIR="$SRC_OBIT/other/tarballs"

# Locate the xmlrpc-c source tarball — it ships as .tgz in the Obit repo
XMLRPC_TAR=$(find "$TARBALLS_DIR" -maxdepth 1 \
    \( -name "xmlrpc-c*.tgz" -o -name "xmlrpc-c*.tar*" \) 2>/dev/null | head -1)

if [ -z "$XMLRPC_TAR" ]; then
    echo "[build-xmlrpc] ERROR: No xmlrpc-c tarball found in $TARBALLS_DIR"
    echo "  Expected something like: $TARBALLS_DIR/xmlrpc-c-<version>.tgz"
    echo "  Ensure you have cloned the Obit repository first (run clone-repo)."
    exit 1
fi

echo "[build-xmlrpc] Found tarball: $XMLRPC_TAR"

INSTALL_PREFIX="$BASE/tmp/xmlrpc-install"
XMLRPC_BUILD="$BASE/tmp/xmlrpc-build"
mkdir -p "$XMLRPC_BUILD" "$INSTALL_PREFIX"

# Always extract fresh — if we skip extraction we risk patching a stale
# partially-built tree where configure may have already regenerated bool.h
echo "[build-xmlrpc] Extracting $XMLRPC_TAR → $XMLRPC_BUILD"
rm -rf "$XMLRPC_BUILD"
mkdir -p "$XMLRPC_BUILD"
tar -xf "$XMLRPC_TAR" --strip-components=1 -C "$XMLRPC_BUILD"

cd "$XMLRPC_BUILD"

# ---- patch 1: config.sub / config.guess ------------------------------------
# xmlrpc-c 1.06.18 (2008) predates Apple Silicon. Refresh from conda automake.
AUTOMAKE_SHARE="$(ls -d "${CONDA_PREFIX}"/share/automake-* 2>/dev/null | tail -1)"
if [ -n "$AUTOMAKE_SHARE" ] && [ -f "$AUTOMAKE_SHARE/config.sub" ]; then
    echo "[build-xmlrpc] Refreshing config.sub/config.guess from $AUTOMAKE_SHARE"
    find . -name "config.sub"   -exec cp "$AUTOMAKE_SHARE/config.sub"   {} \;
    find . -name "config.guess" -exec cp "$AUTOMAKE_SHARE/config.guess" {} \;
else
    echo "[build-xmlrpc] WARNING: automake share dir not found; config.sub may be stale"
fi

# ---- patch 3: curl/types.h --------------------------------------------------
CURL_TRANSPORT="lib/curl_transport/xmlrpc_curl_transport.c"
if [ -f "$CURL_TRANSPORT" ] && grep -q "curl/types.h" "$CURL_TRANSPORT"; then
    echo "[build-xmlrpc] Patching out obsolete #include <curl/types.h>"
    sed -i.bak '/#include <curl\/types\.h>/d' "$CURL_TRANSPORT"
fi

# ---- patch 4: CURLOPT_SSLENGINE_DEFAULT ------------------------------------
if [ -f "$CURL_TRANSPORT" ] && grep -q "CURLOPT_SSLENGINE_DEFAULT" "$CURL_TRANSPORT"; then
    echo "[build-xmlrpc] Patching out removed CURLOPT_SSLENGINE_DEFAULT call"
    sed -i.bak2 '/CURLOPT_SSLENGINE_DEFAULT/d' "$CURL_TRANSPORT"
fi

# ---- platform RPATH flag ----------------------------------------------------
case "$(uname -s)" in
    Darwin|Linux)
        RPATH_FLAG="-Wl,-rpath,$CONDA_PREFIX/lib"
        ;;
    *)
        RPATH_FLAG=""
        ;;
esac

NPROC="${NPROC:-$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 4)}"

# ---- configure --------------------------------------------------------------
echo "[build-xmlrpc] Configuring xmlrpc-c with prefix=$INSTALL_PREFIX"
# xmlrpc-c's Makefiles hardcode their own CFLAGS and ignore what configure
# receives. The only reliable way to inject -std=c11 is via a CC wrapper.
cat > "$XMLRPC_BUILD/cc-wrapper" <<'WRAPPER'
#!/bin/sh
exec gcc -std=c11 -fPIC "$@"
WRAPPER
chmod +x "$XMLRPC_BUILD/cc-wrapper"

./configure \
    --prefix="$INSTALL_PREFIX" \
    --disable-cplusplus \
    --disable-wininet-client \
    --disable-libwww-client \
    --enable-curl-client \
    CC="$XMLRPC_BUILD/cc-wrapper" \
    CPPFLAGS="-I$CONDA_PREFIX/include" \
    LDFLAGS="-L$CONDA_PREFIX/lib $RPATH_FLAG" \
    CFLAGS="-std=c11 -Wno-implicit-function-declaration -Wno-error" \
    PKG_CONFIG_PATH="$CONDA_PREFIX/lib/pkgconfig"

# ---- build only what Obit needs ---------------------------------------------
# Build include headers, libraries, and core src only — skip examples and
# tools which have additional compatibility issues and aren't needed by Obit.
echo "[build-xmlrpc] Building xmlrpc-c libraries (NPROC=$NPROC)"
make -j"$NPROC" -C include/
make -j"$NPROC" -C lib/
make -j"$NPROC" -C src/

# ---- install ----------------------------------------------------------------
echo "[build-xmlrpc] Installing xmlrpc-c → $INSTALL_PREFIX"
make -C include/ install
make -C lib/     install
make -C src/     install

echo "[build-xmlrpc] Done. xmlrpc-c installed at $INSTALL_PREFIX"
