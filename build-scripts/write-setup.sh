#!/usr/bin/env bash
# build-scripts/write-setup.sh
#
# Writes setup.sh (bash/sh) and setup.csh (csh/tcsh) into the repo root.
# Source whichever is appropriate before running any Obit tool:
#
#   source setup.sh      # bash / zsh
#   source setup.csh     # tcsh / csh

set -euo pipefail

BASE="$(pwd)"
SRC_OBIT="$BASE/src/Obit"
OBIT_HOME="$SRC_OBIT/ObitSystem/Obit"
OPT_PREFIX="$SRC_OBIT/opt"
XMLRPC_LIB="$BASE/tmp/xmlrpc-install/lib"

# ---------- setup.sh (bash / sh) -------------------------------------------
PIXI_CONDA_PREFIX="$(pixi run bash -c 'echo $CONDA_PREFIX' 2>/dev/null || echo "$BASE/.pixi/envs/default")"

cat > "$BASE/setup.sh" <<EOF
#!/bin/sh
# Setup environment to run Obit software built with pixi.
# Source this file before running any Obit command:
#   source setup.sh

OBIT="$OBIT_HOME"
export OBIT

OBITINSTALL="$SRC_OBIT"
export OBITINSTALL

# Python module search path for ObitTalk and direct Python usage
PYTHONPATH="$OBIT_HOME/python:$OPT_PREFIX/share/obittalk/python\${PYTHONPATH:+:\$PYTHONPATH}"
export PYTHONPATH

# Prepend Obit binaries and pixi Python to PATH
PATH="$SRC_OBIT/bin:$PIXI_CONDA_PREFIX/bin:\$PATH"
export PATH

# Runtime library paths
case "\$(uname -s)" in
    Darwin)
        DYLD_LIBRARY_PATH="$PIXI_CONDA_PREFIX/lib:$XMLRPC_LIB\${DYLD_LIBRARY_PATH:+:\$DYLD_LIBRARY_PATH}"
        export DYLD_LIBRARY_PATH
        ;;
    Linux)
        LD_LIBRARY_PATH="$PIXI_CONDA_PREFIX/lib:$XMLRPC_LIB\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
        export LD_LIBRARY_PATH
        ;;
esac

echo "Obit environment configured."
echo "  OBIT=\$OBIT"
echo "  PYTHONPATH=\$PYTHONPATH"
EOF
chmod +x "$BASE/setup.sh"
echo "[write-setup] Wrote setup.sh"

# ---------- setup.csh (csh / tcsh) -----------------------------------------
# Resolve CONDA_PREFIX at write time — csh/tcsh treat undefined variables
# as fatal errors, so we cannot defer expansion to source time.
PIXI_CONDA_PREFIX="$(pixi run bash -c 'echo $CONDA_PREFIX' 2>/dev/null || echo "$BASE/.pixi/envs/default")"

cat > "$BASE/setup.csh" <<EOF
# Setup environment to run Obit software built with pixi.
# Source this file before running any Obit command:
#   source setup.csh

setenv OBIT "$OBIT_HOME"
setenv OBITINSTALL "$SRC_OBIT"
setenv PYTHONPATH "$OBIT_HOME/python:$OPT_PREFIX/share/obittalk/python"

if ( \$?PATH ) then
    setenv PATH "$SRC_OBIT/bin:$PIXI_CONDA_PREFIX/bin:\$PATH"
else
    setenv PATH "$SRC_OBIT/bin:$PIXI_CONDA_PREFIX/bin"
endif

# Runtime library paths
if ( "\`uname -s\`" == "Darwin" ) then
    if ( \$?DYLD_LIBRARY_PATH ) then
        setenv DYLD_LIBRARY_PATH "$PIXI_CONDA_PREFIX/lib:$XMLRPC_LIB:\$DYLD_LIBRARY_PATH"
    else
        setenv DYLD_LIBRARY_PATH "$PIXI_CONDA_PREFIX/lib:$XMLRPC_LIB"
    endif
else
    if ( \$?LD_LIBRARY_PATH ) then
        setenv LD_LIBRARY_PATH "$PIXI_CONDA_PREFIX/lib:$XMLRPC_LIB:\$LD_LIBRARY_PATH"
    else
        setenv LD_LIBRARY_PATH "$PIXI_CONDA_PREFIX/lib:$XMLRPC_LIB"
    endif
endif

echo "Obit environment configured."
echo "  OBIT = $OBIT_HOME"
echo "  PYTHONPATH = $OBIT_HOME/python:$OPT_PREFIX/share/obittalk/python"
EOF
echo "[write-setup] Wrote setup.csh"

echo "[write-setup] Done."
echo "  Run:  source setup.sh    (bash/zsh)"
echo "  or:   source setup.csh   (csh/tcsh)"
