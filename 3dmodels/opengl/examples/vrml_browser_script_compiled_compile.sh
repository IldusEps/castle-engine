#!/bin/bash
set -eu

# Hack to allow calling this script from it's dir.
if [ -f vrml_browser_script_compiled.pasprogram ]; then
  cd ../../../
fi

# Call this from ../../../ (or just use `make examples').

fpc -dRELEASE @kambi.cfg 3dmodels/opengl/examples/vrml_browser_script_compiled.pasprogram
