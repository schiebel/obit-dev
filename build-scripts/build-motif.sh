#!/usr/bin/env bash
# build-scripts/build-motif.sh
#
# Builds OpenMotif 2.3.8 from source against conda X11 libraries.
# On macOS, XQuartz (/opt/X11) must be installed to supply build-time X11
# headers (e.g. X11/Xos.h) that conda-forge's xorg-* runtime packages omit.
# On Linux, all headers come from conda-forge.
#
# The resulting prefix is passed to ObitView's ./configure via
#   --with-motif=$BASE/tmp/motif-install

set -euo pipefail

MOTIF_VERSION="2.3.8"
MOTIF_TARBALL="motif-${MOTIF_VERSION}.tar.gz"
# Standard SourceForge direct-download URL for the latest release file
MOTIF_URL="https://sourceforge.net/projects/motif/files/Motif%20${MOTIF_VERSION}%20Source%20Code/${MOTIF_TARBALL}/download"

BASE="$(pwd)"
BUILD_DIR="$BASE/tmp/motif-build"
INSTALL_PREFIX="$BASE/tmp/motif-install"
TARBALL_CACHE="$BASE/tmp/${MOTIF_TARBALL}"

# ---- preflight: verify conda X11 headers are present -----------------------
# The xorg-libx11 conda-forge package installs Xlib.h at this path.
if [ ! -f "${CONDA_PREFIX}/include/X11/Xlib.h" ]; then
    echo "[build-motif] ERROR: X11 headers not found at ${CONDA_PREFIX}/include/X11/Xlib.h"
    echo "  Ensure xorg-libx11 and friends are listed in pixi.toml and 'pixi install' has been run."
    exit 1
fi
echo "[build-motif] Found X11 headers at ${CONDA_PREFIX}/include/X11 ✓"

# ---- download (skip if cached) ----------------------------------------------
mkdir -p "$BASE/tmp"
if [ ! -f "$TARBALL_CACHE" ]; then
    echo "[build-motif] Downloading OpenMotif ${MOTIF_VERSION} from SourceForge"
    curl -fsSL -o "$TARBALL_CACHE" "$MOTIF_URL"
else
    echo "[build-motif] Using cached tarball: $TARBALL_CACHE"
fi

# ---- extract ----------------------------------------------------------------
echo "[build-motif] Extracting ${MOTIF_TARBALL} → $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
tar -xf "$TARBALL_CACHE" --strip-components=1 -C "$BUILD_DIR"

# ---- platform flags ---------------------------------------------------------
case "$(uname -s)" in
    Darwin)
        EXTRA_CFLAGS="-std=gnu11 -Wno-implicit-function-declaration -Wno-incompatible-pointer-types -Wno-int-conversion"
        RPATH_FLAG="-Wl,-rpath,${CONDA_PREFIX}/lib -Wl,-rpath,${INSTALL_PREFIX}/lib"
        if [ -d "/opt/X11/include" ]; then
            # Use XQuartz headers exclusively — conda xorg headers are incomplete
            # (missing XIMResetState, etc.) and mixing them causes conflicts.
            # We still link against conda libs for runtime portability.
            X11_INC="/opt/X11/include"
            X11_LIB="/opt/X11/lib"
            echo "[build-motif] Using XQuartz headers from /opt/X11 (conda libs for linking)"
        else
            echo "[build-motif] ERROR: XQuartz not found at /opt/X11 — required on macOS"
            echo "  Install from https://www.xquartz.org/"
            exit 1
        fi
        ;;
    Linux)
        EXTRA_CFLAGS="-std=gnu11 -Wno-incompatible-pointer-types -Wno-int-conversion"
        RPATH_FLAG="-Wl,-rpath,${CONDA_PREFIX}/lib -Wl,-rpath,${INSTALL_PREFIX}/lib"
        X11_INC="${CONDA_PREFIX}/include"
        X11_LIB="${CONDA_PREFIX}/lib"
        ;;
    *)
        EXTRA_CFLAGS=""
        RPATH_FLAG=""
        X11_INC="${CONDA_PREFIX}/include"
        X11_LIB="${CONDA_PREFIX}/lib"
        ;;
esac

NPROC="${NPROC:-$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 4)}"

# ---- patch makestrs.c -------------------------------------------------------
# GCC 14+ makes incompatible-pointer-types a hard error. makestrs.c uses
# empty () in function pointer arrays (K&R style). Patch to proper prototypes.
MAKESTRS="$BUILD_DIR/config/util/makestrs.c"
if [ -f "$MAKESTRS" ] && ! grep -q "void \(\*headerproc\[\]\)(FILE\*" "$MAKESTRS"; then
    echo "[build-motif] Patching makestrs.c for strict pointer type checking"
    sed -i.bak \
        's/static void (\*headerproc\[\])()/static void (*headerproc[])(FILE*, File*)/' \
        "$MAKESTRS"
    sed -i.bak2 \
        's/static void (\*sourceproc\[\])()/static void (*sourceproc[])(int)/' \
        "$MAKESTRS"
fi

# ---- patch Xpmscan.c --------------------------------------------------------
# GetImagePixels1 uses K&R style with a function-pointer parameter declared as
# int (*storeFunc)(). GCC 14 treats () as "no args" so calling storeFunc(a,b,c)
# is an error. We must patch both the LFUNC forward declaration AND the
# K&R function definition to use a consistent ANSI prototype.
python3 - "$BUILD_DIR/lib/Xm/Xpmscan.c" <<'PYEOF'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
if not path.exists():
    print(f"  skip: {path}")
    sys.exit(0)

src = path.read_text()
orig = src

# 1. Fix the LFUNC forward declaration (line ~92):
#    LFUNC(GetImagePixels1, int, (XImage *image, unsigned int width,
#          unsigned int height, PixelsMap *pmap, int (*storeFunc) ()));
# Replace the storeFunc type inside the LFUNC parens.
src = re.sub(
    r'(LFUNC\s*\(\s*GetImagePixels1\s*,\s*int\s*,\s*\([^)]*?)'
    r'int\s*\(\*storeFunc\)\s*\(\s*\)'
    r'(\s*\)\s*\))',
    r'\1int (*storeFunc)(unsigned long, PixelsMap *, unsigned int *)\2',
    src, flags=re.DOTALL
)

# 2. Rewrite the K&R function definition to ANSI prototype:
src = re.sub(
    r'GetImagePixels1\s*\(\s*image\s*,\s*width\s*,\s*height\s*,\s*pmap\s*,\s*storeFunc\s*\)'
    r'[^{]*?'
    r'\{',
    'GetImagePixels1(XImage *image, unsigned int width, unsigned int height,\n'
    '                PixelsMap *pmap,\n'
    '                int (*storeFunc)(unsigned long, PixelsMap *, unsigned int *))\n'
    '{',
    src, flags=re.DOTALL
)

if src == orig:
    print("  Xpmscan.c: no changes made — printing GetImagePixels1 context:")
    for i, line in enumerate(src.splitlines()):
        if 'GetImagePixels1' in line or 'storeFunc' in line:
            print(f"    {i+1}: {repr(line)}")
    sys.exit(1)

path.write_text(src)
print("  Xpmscan.c: patched LFUNC declaration and K&R definition")
PYEOF

# ---- configure --------------------------------------------------------------
cd "$BUILD_DIR"

# Create a CC wrapper to inject -std=gnu11 into every compilation.
# Motif's Makefiles hardcode CFLAGS and ignore what configure receives.
cat > "$BUILD_DIR/cc-wrapper" <<'WRAPPER'
#!/bin/sh
exec gcc -std=gnu11 "$@"
WRAPPER
chmod +x "$BUILD_DIR/cc-wrapper"

echo "[build-motif] Configuring OpenMotif ${MOTIF_VERSION}"
echo "  prefix:       $INSTALL_PREFIX"
echo "  CONDA_PREFIX: $CONDA_PREFIX"

./configure \
    --prefix="$INSTALL_PREFIX" \
    --disable-static \
    --enable-shared \
    --disable-docs \
    --disable-demos \
    --x-includes="${X11_INC}" \
    --x-libraries="${CONDA_PREFIX}/lib" \
    CC="$BUILD_DIR/cc-wrapper" \
    CPPFLAGS="-I${X11_INC} -I${CONDA_PREFIX}/include" \
    LDFLAGS="-L${CONDA_PREFIX}/lib -L${X11_LIB} ${RPATH_FLAG}" \
    CFLAGS="-I${X11_INC} -I${CONDA_PREFIX}/include ${EXTRA_CFLAGS}" \
    PKG_CONFIG_PATH="${CONDA_PREFIX}/lib/pkgconfig"

# ---- build ------------------------------------------------------------------
echo "[build-motif] Building OpenMotif (NPROC=$NPROC)"
# Build lib only — tools/wml and clients/ build executables that have
# linker issues with the cc-wrapper on Linux. Only the libraries are
# needed for ObitView.
make -j"$NPROC" -C lib

# ---- install ----------------------------------------------------------------
echo "[build-motif] Installing OpenMotif → $INSTALL_PREFIX"
make -C lib install

echo "[build-motif] Done."
echo "  Headers: $INSTALL_PREFIX/include"
echo "  Libs:    $INSTALL_PREFIX/lib"
echo "  Pass --with-motif=$INSTALL_PREFIX to ObitView configure."
