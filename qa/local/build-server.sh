#!/usr/bin/env bash
# Reproducible containerized build of TuGraph.
#
# Usage:
#   qa/local/run.sh build             # clean build, -j2 (safe for an 8 GiB VM)
#   JOBS=4 qa/local/run.sh build      # faster, needs >=12 GiB container RAM
#   CLEAN=0 qa/local/run.sh build     # incremental rebuild
#   BUILD_TYPE=Release qa/local/run.sh build
#   BUILD_TYPE=Release JOBS=1 qa/local/run.sh build  # low-memory mode; NOT
#                                                   # comparable to baselines
#
# Output: build/output/  (lgraph_server, toolkits, liblgraph.so, unit_test,
#                         fma_unit_test, ...)
# Log:    qa-logs/build-<timestamp>.log
#
# This script never modifies source. It is safe to re-run.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/container.sh"

# Default parallelism is deliberately conservative.
#
# TuGraph's `cypher/execution_plan/*.cpp` translation units each need roughly
# 1.5-2.5 GiB of compiler RSS. On the baseline Docker VM (~7.8 GiB RAM) a -j4
# build runs four of them at once, exhausts RAM and swap, and the kernel OOM
# killer terminates cc1plus:
#
#   c++: fatal error: Killed signal terminated program cc1plus
#   make[2]: *** [src/CMakeFiles/lgraph_cypher_lib.dir/.../execution_plan.cpp.o] Error 1
#
# Worse, at -j4 the VM swaps heavily and total throughput drops: measured ~0.6
# TUs/min versus 2 concurrent TUs at -j2 with no swapping. Use JOBS=2 unless you
# have raised the container memory limit.
# Opt-in low-memory lane: BUILD_TYPE=Release JOBS=1 qa/local/run.sh build.
# Release drops debug info and JOBS=1 keeps one heavy TU in flight at a time,
# but the result is NOT comparable to recorded RelWithDebInfo/-j2 baselines.
JOBS="${JOBS:-2}"
BUILD_TYPE="${BUILD_TYPE:-RelWithDebInfo}"
BUILD_PROCEDURE="${BUILD_PROCEDURE:-OFF}"
CLEAN="${CLEAN:-1}"

LOG_DIR="${REPO_ROOT}/qa-logs"
mkdir -p "${LOG_DIR}"
LOG="${LOG_DIR}/build-$(date +%Y%m%d-%H%M%S).log"

if [[ "${JOBS}" -gt 2 ]]; then
    echo "qa: WARNING JOBS=${JOBS}; each heavy C++ TU can need 1.5-2.5 GiB." >&2
    echo "qa:         the baseline Docker VM has ~7.8 GiB and -j4 OOM-killed" >&2
    echo "qa:         cc1plus on cypher/execution_plan.cpp. Raise the container" >&2
    echo "qa:         memory limit before raising JOBS." >&2
fi

IMAGE_ID="$(docker image inspect "${QA_COMPILE_IMAGE}" --format '{{.Id}}' 2>/dev/null || echo unknown)"
COMMIT="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
TREE_STATUS="$(git -C "${REPO_ROOT}" status --porcelain 2>/dev/null || true)"

echo "qa: image      ${QA_COMPILE_IMAGE}"
echo "qa: image_id   ${IMAGE_ID}"
echo "qa: commit     ${COMMIT}"
echo "qa: tree       ${TREE_STATUS:-clean}"
echo "qa: build_type ${BUILD_TYPE}"
echo "qa: jobs       ${JOBS}"
echo "qa: build_proc ${BUILD_PROCEDURE}"
echo "qa: memory     ${QA_DOCKER_EXTRA:-not set}"
echo "qa: clean      ${CLEAN}"
echo "qa: log        ${LOG}"

CLEAN_FLAG="0"
[[ "${CLEAN}" == "1" ]] && CLEAN_FLAG="1"

qa_run_compile bash -lc "
set -euo pipefail
cd '${QA_WORKDIR}'

echo '=== environment ==='
echo \"date:       \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
echo \"arch:       \$(uname -m)\"
echo \"os:         \$(cat /etc/redhat-release 2>/dev/null || uname -sr)\"
echo \"gcc:        \$(gcc --version | head -1)\"
echo \"cmake:      \$(cmake --version | head -1)\"
echo \"protoc:     \$(protoc --version)\"
echo \"python:     \$(python3 --version)\"
echo \"nproc:      \$(nproc)\"
echo \"nofile:     \$(ulimit -n)\"
echo \"map_count:  \$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo n/a)\"

echo '=== build inputs ==='
echo \"commit:     \$(git rev-parse HEAD 2>/dev/null || echo unknown)\"
tree=\$(git status --porcelain 2>/dev/null || true)
echo \"tree:       \${tree:-clean}\"
echo \"jobs:       '${JOBS}'\"
echo \"build_type: '${BUILD_TYPE}'\"
echo \"build_proc: '${BUILD_PROCEDURE}'\"
echo \"image:      '${QA_COMPILE_IMAGE}'\"
echo \"image_id:   '${IMAGE_ID}'\"
echo \"mem_limit:  '${QA_DOCKER_EXTRA:-not set}'\"
echo \"cgroup_mem: \$(cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo n/a)\"

if [[ '${CLEAN_FLAG}' == '1' ]]; then
    echo '=== clean ==='
    rm -rf build
fi
mkdir -p build
cd build

echo '=== cmake configure ==='
# Architecture awareness.
# deps/geax-front-end/CMakeLists.txt:52-61 applies the x86-only -msse4.2 flag
# unless ENABLE_BUILD_ON_AARCH64 is ON. Without it a clean arm64 build fails
# early with: c++: error: unrecognized command line option -msse4.2
# The flag exists upstream but defaults to OFF and is not documented in the
# build instructions. This script detects aarch64 and sets it automatically so the
# build needs no undocumented manual intervention.
case \"\$(uname -m)\" in
    aarch64|arm64) ARCH_OPT=\"-DENABLE_BUILD_ON_AARCH64=ON\" ;;
    *)             ARCH_OPT=\"\" ;;
esac
echo \"cmake arch option: \${ARCH_OPT:-none}\"

cmake .. \
    -DOURSYSTEM=centos7 \
    -DCMAKE_BUILD_TYPE='${BUILD_TYPE}' \
    -DBUILD_PROCEDURE='${BUILD_PROCEDURE}' \
    -DWITH_TESTS=ON \
    \$ARCH_OPT

# Two-phase build: cypher execution_plan TUs need 1.5-2.5 GiB RSS apiece, so
# scheduling several of them at -j4 OOM-kills cc1plus. Serialize that target,
# then build the remaining (cheap) targets with the full JOBS parallelism.
echo '=== make -j1 lgraph_cypher_lib (heavy TUs serialized) ==='
make -j1 lgraph_cypher_lib

echo '=== make -j${JOBS} (remaining targets) ==='
make -j'${JOBS}'

echo '=== build artifacts ==='
ls -la output/ | head -60

# Guard against the build-tree corruption seen in Phase 1: two build containers
# sharing one tree (a killed build leaves its container running) can truncate
# object files to zero bytes, which then get archived and fail at link time.
zeros=\$(find output -name '*.o' -size 0 2>/dev/null | wc -l)
if [ \"\$zeros\" != \"0\" ]; then
    echo \"FATAL: \$zeros zero-byte object file(s) present -- build tree is corrupt.\" >&2
    find output -name '*.o' -size 0 >&2
    exit 1
fi

echo '=== done ==='
date -u +%Y-%m-%dT%H:%M:%SZ
" 2>&1 | tee "${LOG}"

echo
echo "qa: build finished; log at ${LOG}"
