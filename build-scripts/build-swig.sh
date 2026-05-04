#!/usr/bin/env bash
# build-scripts/build-swig.sh
#
# Downloads SWIG 3.0.12 source from SourceForge, builds it against the
# conda-managed pcre library, and installs it into tmp/swig-install/.
#
# This is done on ALL platforms (linux-64, osx-64, osx-arm64) for
# consistency and to guarantee exactly the SWIG version Obit's .i files
# were written for.  The conda SWIG package (whatever version pixi resolves)
# is never invoked during the Obit build — tmp/swig-install/bin is prepended
# to PATH in common-env.sh so the from-source binary takes precedence.
#
# SWIG 3.0.12 was released January 2017.  It predates Apple Silicon but is
# pure C/C++ with a standard autoconf build and compiles cleanly with clang
# on arm64.  Its only mandatory build-time dependency is PCRE (not PCRE2),
# which is available as the `pcre` package on conda-forge.

set -euo pipefail

SWIG_VERSION="3.0.12"
SWIG_TARBALL="swig-${SWIG_VERSION}.tar.gz"
SWIG_URL="https://downloads.sourceforge.net/swig/${SWIG_TARBALL}"
SWIG_MD5="82133dfa7bba75ff9ad98a7046be687c"

BASE="$(pwd)"
BUILD_DIR="$BASE/tmp/swig-build"
INSTALL_PREFIX="$BASE/tmp/swig-install"
TARBALL_CACHE="$BASE/tmp/${SWIG_TARBALL}"

# ---- preflight: pcre headers ------------------------------------------------
# SWIG 3.x requires PCRE (not PCRE2).  conda-forge package is `pcre`.
if [ ! -f "${CONDA_PREFIX}/include/pcre.h" ]; then
    echo "[build-swig] ERROR: pcre.h not found at ${CONDA_PREFIX}/include/pcre.h"
    echo "  Ensure 'pcre' is listed in pixi.toml dependencies and 'pixi install' has been run."
    exit 1
fi
echo "[build-swig] Found PCRE headers at ${CONDA_PREFIX}/include ✓"

# ---- download (skip if cached) ----------------------------------------------
mkdir -p "$BASE/tmp"
if [ ! -f "$TARBALL_CACHE" ]; then
    echo "[build-swig] Downloading SWIG ${SWIG_VERSION} from SourceForge"
    curl -fsSL -o "$TARBALL_CACHE" "$SWIG_URL"
else
    echo "[build-swig] Using cached tarball: $TARBALL_CACHE"
fi

# ---- verify MD5 -------------------------------------------------------------
echo "[build-swig] Verifying MD5 checksum"
case "$(uname -s)" in
    Darwin) ACTUAL_MD5=$(md5 -q "$TARBALL_CACHE") ;;
    Linux)  ACTUAL_MD5=$(md5sum "$TARBALL_CACHE" | awk '{print $1}') ;;
esac
if [ "$ACTUAL_MD5" != "$SWIG_MD5" ]; then
    echo "[build-swig] ERROR: MD5 mismatch!"
    echo "  Expected: $SWIG_MD5"
    echo "  Got:      $ACTUAL_MD5"
    echo "  Deleting corrupt download: $TARBALL_CACHE"
    rm -f "$TARBALL_CACHE"
    exit 1
fi
echo "[build-swig] MD5 OK ✓"

# ---- extract ----------------------------------------------------------------
if [ ! -f "$BUILD_DIR/configure" ]; then
    echo "[build-swig] Extracting ${SWIG_TARBALL} → $BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    tar -xf "$TARBALL_CACHE" --strip-components=1 -C "$BUILD_DIR"
fi

# ---- platform flags ---------------------------------------------------------
case "$(uname -s)" in
    Darwin)
        EXTRA_CFLAGS="-Wno-implicit-function-declaration -Wno-deprecated-non-prototype"
        EXTRA_CXXFLAGS="-Wno-deprecated-non-prototype"
        RPATH_FLAG="-Wl,-rpath,${CONDA_PREFIX}/lib"
        ;;
    Linux)
        EXTRA_CFLAGS=""
        EXTRA_CXXFLAGS=""
        RPATH_FLAG="-Wl,-rpath,${CONDA_PREFIX}/lib"
        ;;
    *)
        EXTRA_CFLAGS=""
        EXTRA_CXXFLAGS=""
        RPATH_FLAG=""
        ;;
esac

NPROC="${NPROC:-$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 4)}"

# ---- configure --------------------------------------------------------------
cd "$BUILD_DIR"

echo "[build-swig] Configuring SWIG ${SWIG_VERSION}"
echo "  prefix:       $INSTALL_PREFIX"
echo "  CONDA_PREFIX: $CONDA_PREFIX"
echo "  arch:         $(uname -m)"

./configure \
    --prefix="$INSTALL_PREFIX" \
    --without-maximum-compile-warnings \
    --without-alllang \
    --with-python="${CONDA_PREFIX}/bin/python" \
    --with-pcre-prefix="${CONDA_PREFIX}" \
    CPPFLAGS="-I${CONDA_PREFIX}/include" \
    LDFLAGS="-L${CONDA_PREFIX}/lib ${RPATH_FLAG}" \
    CFLAGS="-I${CONDA_PREFIX}/include ${EXTRA_CFLAGS}" \
    CXXFLAGS="-I${CONDA_PREFIX}/include ${EXTRA_CXXFLAGS}"

# ---- build ------------------------------------------------------------------
echo "[build-swig] Building SWIG (NPROC=$NPROC)"
make -j"$NPROC"

# ---- install ----------------------------------------------------------------
echo "[build-swig] Installing SWIG → $INSTALL_PREFIX"
make install

echo "[build-swig] Done."
echo "  Binary: $INSTALL_PREFIX/bin/swig"
"$INSTALL_PREFIX/bin/swig" -version
