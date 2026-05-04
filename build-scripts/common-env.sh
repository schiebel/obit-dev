#!/usr/bin/env bash
# build-scripts/common-env.sh
#
# Source this file from each component build script.
# Sets all paths and configure flags that are common across
# Obit, ObitView, and ObitTalk.

# ---- base directories -------------------------------------------------------
BASE="$(pwd)"
SRC_OBIT="$BASE/src/Obit"
OBIT_HOME="$SRC_OBIT/ObitSystem/Obit"      # $OBIT env var expected by configure
XMLRPC_PREFIX="$BASE/tmp/xmlrpc-install"
INSTALL_DIR="$BASE/install"                # where built artefacts land

export OBIT="$OBIT_HOME"
export OBITINSTALL="$SRC_OBIT"            # mirrors the original script convention

# ---- compiler helpers -------------------------------------------------------
# Use whatever compiler the active conda environment exposes.
# On Linux, conda activates gcc_linux-64 which sets CC/CXX automatically.
# On macOS, clang is the default; we honour whatever is already in $CC/$CXX.
export CC="${CC:-gcc}"
export CXX="${CXX:-g++}"

# ---- library search paths via conda -----------------------------------------
export PKG_CONFIG_PATH="${XMLRPC_PREFIX}/lib/pkgconfig:${CONDA_PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

# ---- platform-specific RPATH / linker flags ---------------------------------
case "$(uname -s)" in
    Darwin)
        RPATH_FLAG="-Wl,-rpath,${CONDA_PREFIX}/lib -Wl,-rpath,${XMLRPC_PREFIX}/lib"
        ;;
    Linux)
        RPATH_FLAG="-Wl,-rpath,${CONDA_PREFIX}/lib -Wl,-rpath,${XMLRPC_PREFIX}/lib"
        ;;
    *)
        RPATH_FLAG=""
        ;;
esac

export LDFLAGS="-L${CONDA_PREFIX}/lib -L${XMLRPC_PREFIX}/lib ${RPATH_FLAG} ${LDFLAGS:-}"
export CPPFLAGS="-I${CONDA_PREFIX}/include -I${XMLRPC_PREFIX}/include ${CPPFLAGS:-}"
# Obit source uses deprecated GLib macros (g_memmove etc.) that GCC treats as
# errors via #pragma GCC warning. Suppress deprecated-declarations warnings.
export CFLAGS="${CFLAGS:+$CFLAGS }-Wno-deprecated-declarations -Wno-error"

# ---- LD_LIBRARY_PATH / DYLD_LIBRARY_PATH ------------------------------------
case "$(uname -s)" in
    Darwin)
        export DYLD_LIBRARY_PATH="${CONDA_PREFIX}/lib:${XMLRPC_PREFIX}/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
        ;;
    Linux)
        export LD_LIBRARY_PATH="${CONDA_PREFIX}/lib:${XMLRPC_PREFIX}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        ;;
esac

# ---- configure flag helpers -------------------------------------------------
# Each flag points Obit's autoconf at the conda-managed library.
WITH_CFITSIO="--with-cfitsio=${CONDA_PREFIX}"
WITH_FFTW="--with-fftw3=${CONDA_PREFIX}"
WITH_GSL="--with-gsl=${CONDA_PREFIX}"
WITH_GLIB="--with-glib-prefix=${CONDA_PREFIX}"
WITH_CURL="--with-curl=${CONDA_PREFIX}"
WITH_XMLRPC="--with-xmlrpc=${XMLRPC_PREFIX}"
WITH_ZLIB="--with-zlib=${CONDA_PREFIX}"
WITH_BOOST="--with-boost=${CONDA_PREFIX}"
WITH_PYTHON="--with-python=${CONDA_PREFIX}"

# Motif: always built from source by build-motif.sh into tmp/motif-install/.
# Individual build scripts (build-obitview.sh) set --with-motif directly.

# WVR (ALMA water-vapour radiometer library) — optional; skip if source absent
WVR_SRC="$SRC_OBIT/other"   # bundled WVR lives in the other/ tree
WITH_WVR=""  # populated by individual build scripts if needed

# ---- SWIG 3.0.12 (built from source, all platforms) -------------------------
# Prepend tmp/swig-install/bin so the from-source binary shadows any conda
# SWIG package that pixi may have installed.
SWIG_PREFIX="$BASE/tmp/swig-install"
if [ ! -f "$SWIG_PREFIX/bin/swig" ]; then
    echo "[common-env] ERROR: SWIG not found at $SWIG_PREFIX/bin/swig"
    echo "  Run 'pixi run build-swig' first, or use 'pixi run build-all'."
    exit 1
fi
export PATH="$SWIG_PREFIX/bin:$PATH"
echo "[common-env] SWIG: $(swig -version 2>&1 | head -2 | tr '\n' ' ')"

# ---- parallel build ---------------------------------------------------------
NPROC="${NPROC:-$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 4)}"

echo "[common-env] BASE=$BASE"
echo "[common-env] CONDA_PREFIX=$CONDA_PREFIX"
echo "[common-env] CC=$CC  CXX=$CXX"
echo "[common-env] LDFLAGS=$LDFLAGS"
echo "[common-env] CPPFLAGS=$CPPFLAGS"
