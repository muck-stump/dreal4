#!/usr/bin/env bash
#
#  Copyright 2017 Toyota Research Institute
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
# Installs everything needed to build dReal on macOS (Intel and Apple
# Silicon) from this repository. Safe to re-run.
#
# Expected environment:
#   - Xcode Command Line Tools  (install with: xcode-select --install)
#   - Homebrew                 (https://brew.sh)
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo 'This script must NOT be run as root' >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v brew >/dev/null 2>&1; then
  echo 'error: Homebrew not found. Install it from https://brew.sh first.' >&2
  exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
  echo 'error: Xcode Command Line Tools not found. Run: xcode-select --install' >&2
  exit 1
fi

# Toolchain and libraries:
#   bazelisk  bazel launcher; picks the Bazel version from .bazelversion
#   bison, flex  parser generators, referenced by the lexyacc toolchain
#                paths in third_party/com_github_google_kythe/tools/build_rules
#   pkg-config   used by Bazel's pkg_config_repository to find the libraries
#   gmp, clp, nlopt  numerical libraries dReal links against
#   python       Python bindings and the Python-based tests
brew install bazelisk bison flex gmp clp nlopt pkg-config python

# ibex 2.7.4 is the interval-arithmetic library dReal links against. It is
# not installable from the usual places any longer:
#   - homebrew-core only ships ibex 2.9.x, which has an incompatible API;
#   - third-party taps only carry an Intel-Mac-era formula.
# So we publish our own patched copy of the formula (see ibex@2.7.4.rb in
# this directory) into a small local tap. Homebrew discovers a tap purely
# from the directory layout, no "brew tap" invocation is needed.
IBEX_TAP_DIR="$(brew --repository dreal4/local)/Formula"
mkdir -p "${IBEX_TAP_DIR}"
cp "${SCRIPT_DIR}/ibex@2.7.4.rb" "${IBEX_TAP_DIR}/"

if brew list --versions dreal4/local/ibex@2.7.4 >/dev/null 2>&1; then
  echo 'ibex@2.7.4 is already installed.'
  echo "(If you updated ${SCRIPT_DIR}/ibex@2.7.4.rb, refresh it with:"
  echo "  brew reinstall dreal4/local/ibex@2.7.4)"
else
  brew install dreal4/local/ibex@2.7.4
fi

cat <<'EOF'

All prerequisites are installed. Next steps:

  bazel build //...                     # build dReal (Bazel comes from bazelisk)
  bazel test //...                      # run the test suite
  ./bazel-bin/dreal/dreal <file.smt2>   # solve an .smt2 file

EOF
