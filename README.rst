Obit Pixi Build
===============

A `pixi <https://pixi.prefix.dev/latest/>`_ build environment for
`Obit Astronomy Software <https://github.com/bill-cotton/Obit>`_ (Bill Cotton, NRAO).

Supports **Linux x86-64**, **macOS Intel (x86-64)**, and **macOS Apple Silicon (arm64)**.

----

Setting up Pixi
---------------

Pixi is a fast, cross-platform package manager built on top of conda-forge.
If you do not already have it installed, run::

    curl -fsSL https://pixi.sh/install.sh | bash

Then restart your shell (or ``source ~/.bashrc`` / ``source ~/.zshrc``) so that
the ``pixi`` command is on your ``PATH``. Verify the installation::

    pixi --version

.. note::

   **macOS:** On Apple Silicon and Intel Macs, XQuartz must be installed
   for the OpenMotif build. It provides complete X11 development headers that
   conda-forge's xorg packages omit. Download from https://www.xquartz.org/
   and log out/in once after installing before running any build tasks.

----

Quick start — full build
------------------------

::

    # 1. Install all conda-forge dependencies into the pixi environment
    pixi install

    # 2. Full build: clone → xmlrpc-c → SWIG → Obit → ObitView → ObitTalk
    pixi run build-all

    # 3. Write runtime environment files
    pixi run write-setup

    # 4. Activate runtime environment in your shell
    source setup.sh        # bash / zsh
    # — or —
    source setup.csh       # csh / tcsh

``build-all`` runs the complete dependency chain automatically.
A first run on a clean machine takes 10–30 minutes depending on CPU count.

----

Building individual components
-------------------------------

Each task declares its dependencies in ``pixi.toml``. When you run an
individual task, pixi automatically runs any upstream tasks that have not
yet completed.

.. list-table::
   :header-rows: 1
   :widths: 30 35 35

   * - Command
     - Also runs
     - What it builds
   * - ``pixi run clone-repo``
     - —
     - Clones ``github.com/bill-cotton/Obit`` into ``src/Obit/``
   * - ``pixi run build-swig``
     - ``clone-repo``
     - SWIG 3.0.12 from source
   * - ``pixi run build-xmlrpc``
     - ``clone-repo``
     - bundled xmlrpc-c into ``tmp/xmlrpc-install/``
   * - ``pixi run build-motif``
     - ``clone-repo``
     - OpenMotif 2.3.8 into ``tmp/motif-install/``
   * - ``pixi run build-obit``
     - ``clone-repo``, ``build-swig``, ``build-xmlrpc``
     - Obit C library + Python SWIG bindings
   * - ``pixi run build-obitview``
     - ``build-obit``, ``build-motif``
     - ObitView image display GUI
   * - ``pixi run build-obittalk``
     - ``build-obit``
     - ObitTalk Python interface
   * - ``pixi run build-all``
     - everything above
     - Runs the full chain
   * - ``pixi run build-core``
     - ``clone-repo``, ``build-swig``, ``build-xmlrpc``, ``build-obit``
     - Obit C library only — no GUI, no ObitTalk

So for example, ``pixi run build-obitview`` will automatically ensure
``clone-repo``, ``build-swig``, ``build-xmlrpc``, ``build-obit``, and
``build-motif`` have all run first.

----

Inspecting dependency versions
-------------------------------

To see which version of a conda-forge package is installed in the build
environment, use ``pixi list``::

    # Show all installed packages and their versions
    pixi list

    # Filter to specific packages
    pixi list | grep python
    pixi list | grep -E "cfitsio|fftw|gsl|glib|libcurl|gcc"

To inspect non-conda components built from source::

    # SWIG version
    tmp/swig-install/bin/swig -version 2>&1 | head -2

    # xmlrpc-c version (from the build script)
    grep "XMLRPC_VERSION=" build-scripts/build-xmlrpc.sh

    # OpenMotif version
    grep "MOTIF_VERSION=" build-scripts/build-motif.sh

    # Obit revision
    cat src/Obit/ObitSystem/Obit/src/ObitVersion.c

To test loading of Obit::

    pixi run bash -c "PYTHONPATH=src/Obit/ObitSystem/Obit/python python -c \"import _Obit; print('hello')\""

----

What happens under the hood
----------------------------

.. list-table::
   :header-rows: 1
   :widths: 20 35 45

   * - Task
     - Script
     - What it does
   * - ``clone-repo``
     - ``build-scripts/clone-repo.sh``
     - ``git clone`` Obit into ``src/Obit/``
   * - ``build-swig``
     - ``build-scripts/build-swig.sh``
     - Builds SWIG 3.0.12 from source on all platforms for consistent
       Python binding generation
   * - ``build-xmlrpc``
     - ``build-scripts/build-xmlrpc.sh``
     - Builds the bundled xmlrpc-c from ``src/Obit/other/`` into
       ``tmp/xmlrpc-install/``. Built with ``-fPIC`` so its objects can
       be merged into ``libObit.so``.
   * - ``build-motif``
     - ``build-scripts/build-motif.sh``
     - Downloads OpenMotif 2.3.8 and builds it against conda X11 libs
       into ``tmp/motif-install/``. On macOS, XQuartz provides complete
       build-time headers.
   * - ``build-obit``
     - ``build-scripts/build-obit.sh``
     - ``./configure`` + ``make`` in ``ObitSystem/Obit/``. Builds the C
       library, tasks, and Python SWIG bindings. Also creates
       ``libObit.so`` by merging Obit and xmlrpc-c static archives,
       which is required for ``import _Obit`` in Python.
   * - ``build-obitview``
     - ``build-scripts/build-obitview.sh``
     - ``./configure`` + ``make`` in ``ObitSystem/ObitView/``. Links
       against from-source Motif and the Obit library.
   * - ``build-obittalk``
     - ``build-scripts/build-obittalk.sh``
     - ``./configure`` + ``make install`` in ``ObitSystem/ObitTalk/``.
       Installs Python modules under
       ``src/Obit/opt/share/obittalk/python/``.
   * - ``write-setup``
     - ``build-scripts/write-setup.sh``
     - Writes ``setup.sh`` and ``setup.csh`` with ``OBIT``,
       ``PYTHONPATH``, ``PATH``, and library-path variables.

----

Dependency strategy
--------------------

The original ``InstallObit.sh`` builds all third-party libraries from
source tarballs bundled in ``other/``. This pixi setup replaces those
with conda-forge packages wherever possible:

.. list-table::
   :header-rows: 1
   :widths: 15 35 50

   * - Library
     - Source
     - Notes
   * - CFITSIO
     - conda-forge ``cfitsio``
     -
   * - FFTW
     - conda-forge ``fftw``
     - version 3
   * - GSL
     - conda-forge ``gsl``
     -
   * - GLIB
     - conda-forge ``glib``
     -
   * - CURL
     - conda-forge ``libcurl``
     -
   * - ZLIB
     - conda-forge ``zlib``
     -
   * - BOOST
     - conda-forge ``boost-cpp``
     - headers only, for WVR
   * - PYTHON
     - conda-forge ``python``
     - 3.8–3.11 (SWIG ABI constraint)
   * - MOTIF
     - built from source (OpenMotif 2.3.8)
     - not on conda-forge for macOS
   * - XMLRPC-C
     - built from bundled source
     - not on conda-forge
   * - SWIG
     - built from source (3.0.12)
     - Obit's Python bindings require SWIG 3.x

----

Platform notes
--------------

macOS (Apple Silicon and Intel)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- **XQuartz is required** for the OpenMotif build. It provides complete
  X11 headers (``Xlib.h``, ``Xosdefs.h``, etc.) that conda-forge's xorg
  packages omit. Runtime linking uses conda's X11 libraries.
- The build uses CC wrapper scripts to inject ``-std=gnu11`` for Motif and
  ``-std=gnu89`` for Obit, since both codebases predate modern C standards
  and use identifiers (e.g. ``bool`` as a variable name, empty ``()``
  function pointer declarations) that conflict with C99 and later.

Linux
~~~~~

- OpenMotif is built from source for consistency with macOS, against
  conda-managed X11 libraries. XQuartz is not required.
- All objects are compiled with ``-fPIC`` to support ``libObit.so``.

----

AIPS
----

Obit can read/write AIPS data directly, but **AIPS does not need to be
installed** to build or run Obit. Obit's native data format is FITS.
AIPS interoperability can be added later by setting the ``DA00`` and
``AIPSDIR`` environment variables after AIPS is installed separately.

----

Cleaning up
-----------

::

    pixi run clean      # remove build artefacts; keeps downloaded tarballs and source
    pixi run clean-all  # remove everything including cloned source
