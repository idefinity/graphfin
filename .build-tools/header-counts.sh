#!/bin/bash
# Optional, opt-in header-count sampler. It is never called by any build.
#
# Usage:
#   .build-tools/header-counts.sh
#   LGRAPH_BUILD_LOGS=/path/to/logs .build-tools/header-counts.sh
#   LGRAPH_REPO_ROOT=/workspace /results/header-counts.sh
#
# Runs `c++ -H -fsyntax-only` on three representative translation units and
# writes the number of headers each one pulls in to
# $LGRAPH_BUILD_LOGS/header-counts.txt. The compiler flags come straight from
# the build tree's generated flags.make, so the header closure matches the real
# build instead of a guessed include path list. Syntax errors are ignored: -H
# still reports the headers it managed to open before the error.
set -uo pipefail
# The gate may copy this script next to its results, so BASH_SOURCE is not
# necessarily inside the repo. Allow an explicit root; keep the in-repo default.
R=${LGRAPH_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
B=${BUILD_DIR:-$R/build}
L=${LGRAPH_BUILD_LOGS:-$R/.build-logs}
CXX=${CXX:-c++}
FLAGS_MAKE=${FLAGS_MAKE:-$B/src/CMakeFiles/lgraph_cypher_lib.dir/flags.make}
SERVER_FLAGS_MAKE=${SERVER_FLAGS_MAKE:-$B/src/CMakeFiles/lgraph_server_lib.dir/flags.make}
if [ ! -f "$R/CMakeCache.txt" ] && [ ! -f "$FLAGS_MAKE" ] \
   && [ ! -f "$SERVER_FLAGS_MAKE" ]; then
    echo "header-counts: repo root '$R' has no CMakeCache.txt and no flags.make." >&2
    echo "header-counts: expected flags.make at '$FLAGS_MAKE' (server: '$SERVER_FLAGS_MAKE')." >&2
    echo "header-counts: set LGRAPH_REPO_ROOT, BUILD_DIR or FLAGS_MAKE to a configured build." >&2
fi
WORKDIR=$B
[ -d "$WORKDIR" ] || WORKDIR=$R
mkdir -p "$L"
OUT="$L/header-counts.txt"
TMP=$(mktemp)

_cmake_flags() {
    local key=$1 file=$2
    grep "^$key[[:space:]]*=" "$file" 2>/dev/null \
        | sed "s/^$key[[:space:]]*=[[:space:]]*//" || true
}

# Drop GCC-only --param <x> pairs, as .build-tools/flags.sh does. Keep every
# other flag verbatim, including -std from flags.make.
_norm_flags() {
    local a skip=0
    for a in "$@"; do
        if [ "$skip" -eq 1 ]; then skip=0; continue; fi
        case "$a" in
            --param) skip=1 ;;
            --param=*|-ftrack-macro-expansion=*) ;;
            *) printf '%s\n' "$a" ;;
        esac
    done
}

TU_FLAGS=()
_load_flags() {
    local file=$1 defs incs flags
    TU_FLAGS=()
    if [ ! -f "$file" ]; then
        echo "header-counts: flags.make not found: $file" >&2
        return 0
    fi
    defs=$(_cmake_flags CXX_DEFINES "$file")
    incs=$(_cmake_flags CXX_INCLUDES "$file")
    flags=$(_cmake_flags CXX_FLAGS "$file")
    while IFS= read -r line; do
        TU_FLAGS+=("$line")
    done < <(_norm_flags $defs $incs $flags)
}

: > "$OUT"
for entry in \
    "lgraph_cypher_lib:src/cypher/execution_plan/execution_plan.cpp" \
    "lgraph_server_lib:src/restful/server/rest_server.cpp" \
    "lgraph_server_lib:src/http/http_server.cpp"; do
    target=${entry%%:*}
    src=${entry#*:}
    if [ "$target" = "lgraph_cypher_lib" ]; then
        _load_flags "$FLAGS_MAKE"
    else
        _load_flags "$SERVER_FLAGS_MAKE"
    fi
    # -H writes its dot-prefixed header trace to stderr on GCC but some
    # drivers use stdout; capture both so the count never depends on that.
    if [ "${#TU_FLAGS[@]}" -gt 0 ]; then
        ( cd "$WORKDIR" && "$CXX" "${TU_FLAGS[@]}" -H -fsyntax-only "$R/$src" ) \
            >"$TMP" 2>&1 || true
    else
        : > "$TMP"
    fi
    # GNU grep 2.20 BRE treats \+ as a literal plus; use ERE for dot-prefixed
    # -H lines. Same for sed, so both total and unique counts are portable.
    total=$(grep -Ec '^\.+[[:space:]]' "$TMP" || true)
    unique=$(sed -En 's/^\.+[[:space:]]*//p' "$TMP" | LC_ALL=C sort -u | wc -l | tr -d ' ')
    if [ "$total" -eq 0 ]; then
        echo "header-counts: no -H header lines for $src" >&2
    fi
    printf 'headers\t%s\t%s\ttotal=%s\tunique=%s\n' \
        "$target" "$src" "$total" "$unique" >> "$OUT"
done
rm -f "$TMP"
echo "header counts written to $OUT"
