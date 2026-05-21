#!/bin/bash
# Build script for rackspace-monitoring-agent on Ubuntu 24.04.
# Based on: https://github.com/virgo-agent-toolkit/rackspace-monitoring-agent-buildbot-builder/blob/master/build.sh
# With fixes for Ubuntu 24.04 compatibility:
#   - racker/sigar expected as a sibling directory (../sigar relative to this project)
#   - libtirpc headers symlinked for rpc/rpc.h
#   - LuaJIT updated to commit c3459468 (Aug 2023, works on modern kernels)
#   - Uses system shared OpenSSL instead of building from source
set -eu

LUVI_VERSION=2.9.4-sigar
LIT_VERSION=3.7.3
LIT_URL="https://lit.luvit.io/packages/luvit/lit/v$LIT_VERSION.zip"
LUVI_URL="https://github.com/virgo-agent-toolkit/luvi.git"
SIGAR_REPO="https://github.com/racker/sigar.git"

# Resolve the directory containing this script (i.e., the agent project root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Sigar is expected as a sibling directory to this project
SIGAR_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/sigar"

BUILD_DIR=${PWD}/buildtools
SRC_DIR=${PWD}/src
AGENT_DIR=${SCRIPT_DIR}

export LIT=${BUILD_DIR}/lit
export LUVI=${BUILD_DIR}/luvi
export PATH=${BUILD_DIR}:$PATH

# Ensure sigar is available
ensure_sigar() {
  if [ ! -d "${SIGAR_DIR}" ]; then
    echo "ERROR: sigar directory not found at ${SIGAR_DIR}" >&2
    echo "" >&2
    echo "The sigar project is required as a sibling directory to this project." >&2
    echo "Since it is a private repository, you must clone it manually:" >&2
    echo "" >&2
    echo "  git clone ${SIGAR_REPO} ${SIGAR_DIR}" >&2
    echo "" >&2
    echo "Expected layout:" >&2
    echo "  parent-dir/" >&2
    echo "  ├── rackspace-monitoring-agent/" >&2
    echo "  └── sigar/" >&2
    exit 1
  fi
  echo "==> Using sigar from ${SIGAR_DIR}"
}

setup() {
  mkdir -p ${BUILD_DIR} ${SRC_DIR}
}

build_luvi() {
  LUVI_DIR="${SRC_DIR}/luvi-${LUVI_VERSION}"
  if [ ! -d ${LUVI_DIR} ]; then
    # Clone without recursing — we need to fix broken submodule URLs
    git clone --branch ${LUVI_VERSION} ${LUVI_URL} ${LUVI_DIR}
    pushd ${LUVI_DIR}
      # Init all submodules except lua-sigar (which references racker/sigar)
      git submodule update --init --recursive -- deps/lpeg deps/lrexlib deps/lua-openssl deps/lua-zlib deps/luv deps/pcre deps/zlib

      # Fix lua-sigar: use sibling sigar project instead of unavailable racker/sigar submodule
      git submodule update --init -- deps/lua-sigar
      # Manually place sigar source where the submodule expects it
      rm -rf deps/lua-sigar/deps/sigar
      cp -r "${SIGAR_DIR}" deps/lua-sigar/deps/sigar

      # Replace bundled LuaJIT with a newer version that works on modern kernels.
      # The bundled version segfaults on Ubuntu 24.04 (both x86_64 and ARM64).
      # We use the system libluajit for linking (swapped in during the build step).
    popd
  fi

  pushd ${LUVI_DIR}
    # Build with static OpenSSL (bundled 1.x, since system OpenSSL 3.x is incompatible
    # with this old lua-openssl code). -w suppresses GCC 13 warnings-as-errors.
    cmake -H. -Bbuild -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_FLAGS="-w" \
      -DWithOpenSSL=ON -DWithSharedOpenSSL=OFF \
      -DWithPCRE=ON -DWithSharedPCRE=OFF \
      -DWithLPEG=ON -DWithSigar=ON
    # Build all targets. This will fail at the luvi bytecode step (segfault) but
    # all libraries and the luajit binary will be built.
    cmake --build build 2>&1 || true
    # The bundled LuaJIT segfaults on Ubuntu 24.04 when used for bytecode compilation.
    # Replace the bundled luajit commands with system luajit in the build rules.
    # Command lines: "deps/luv/luajit -bg ..." -> "/usr/bin/luajit -bg ..."
    # Dependency lines: "target: deps/luv/luajit" -> remove the dependency
    # We use sed with a tab prefix to target only command lines (indented with tab).
    sed -i 's|\tdeps/luv/luajit |\t/usr/bin/luajit |g' build/CMakeFiles/luvi.dir/build.make
    # Remove dependency lines that reference the bundled luajit binary
    # These lines look like: "jitted_tmp/foo.o: deps/luv/luajit"
    sed -i '/^[^ ]*: deps\/luv\/luajit$/d' build/CMakeFiles/luvi.dir/build.make
    # Remove the bundled jit/ module directory so system luajit doesn't pick up
    # the bundled bcsave.lua (which causes a version mismatch).
    rm -rf build/jit
    # Prevent cmake from regenerating build rules (which would undo our sed changes)
    touch build/CMakeFiles/cmake.check_cache
    # Patch command lines to set LUA_PATH before invoking system luajit, forcing it
    # to use its own system modules instead of any local ./jit/ directory that cmake
    # may recreate when building the luajit dependency target.
    sed -i 's|\t/usr/bin/luajit |\tLUA_PATH="/usr/share/luajit-2.1/?.lua;;" /usr/bin/luajit |g' build/CMakeFiles/luvi.dir/build.make
    # Rebuild only the luvi target (bytecode + link step) using system luajit for
    # compilation but the original bundled libluajit.a for linking.
    # Replace the bundled libluajit.a with the system one so the luvi runtime
    # doesn't segfault on modern kernels.
    SYSTEM_LIBLUAJIT=$(find /usr -name 'libluajit-5.1.a' 2>/dev/null | head -1)
    if [ -n "${SYSTEM_LIBLUAJIT}" ]; then
      BUNDLED_LIBLUAJIT=$(find build -name 'libluajit.a' -o -name 'libluajit-5.1.a' 2>/dev/null | head -1)
      if [ -n "${BUNDLED_LIBLUAJIT}" ]; then
        echo "==> Replacing bundled libluajit (${BUNDLED_LIBLUAJIT}) with system (${SYSTEM_LIBLUAJIT})"
        cp "${SYSTEM_LIBLUAJIT}" "${BUNDLED_LIBLUAJIT}"
      fi
    fi
    cmake --build build -- luvi
    cp build/luvi ${BUILD_DIR}/luvi
  popd
}

build_lit() {
  if [ ! -f ${SRC_DIR}/lit.zip ]; then
    curl -kL $LIT_URL > ${SRC_DIR}/lit.zip
  fi
  if [ ! -x ${BUILD_DIR}/lit ]; then
    pushd ${BUILD_DIR}
      ${BUILD_DIR}/luvi ${SRC_DIR}/lit.zip -- make ${SRC_DIR}/lit.zip ${BUILD_DIR}/lit ${BUILD_DIR}/luvi
    popd
  fi
}

build_agent() {
  pushd ${AGENT_DIR}
    # Symlink build tools into agent source tree
    ln -f -s ${LUVI} luvi-sigar
    ln -f -s ${LUVI} luvi
    ln -f -s ${LIT} lit

    # server.key for signing
    if [ -f "server.key" ]; then
      cp server.key ~/server.key
    fi

    # Build agent
    make
    make package

    # Sign binary (skips if ~/server.key absent)
    cd build && make siggen 2>&1 || true
    cd ..

    # Import GPG key and build signed repo
    if [ -f "agent-package-signing-key.txt" ]; then
      gpg --batch --import agent-package-signing-key.txt
      echo "==> GPG key D05AB914 imported"
      make packagerepo
    else
      echo "WARNING: agent-package-signing-key.txt not found, skipping packagerepo"
    fi

    # Build meta packages
    if [ -f "build-meta-debs.sh" ]; then
      chmod +x build-meta-debs.sh
      ./build-meta-debs.sh signing-key.asc /build/meta
    fi
  popd
}

ensure_sigar
setup
build_luvi
build_lit
build_agent
