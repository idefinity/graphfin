#!/bin/bash
# Optional, opt-in header-count sampler. It is never called by any build.
#
# Usage:
#   .build-tools/header-counts.sh
#   LGRAPH_BUILD_LOGS=/path/to/logs .build-tools/header-counts.sh
#
# Runs `c++ -H -fsyntax-only` on three representative translation units and
# writes the number of headers each one pulls in to
# $LGRAPH_BUILD_LOGS/header-counts.txt. The compiler flags come straight from
# the build tree's generated flags.make, so the header closure matches the real
# build instead of a guessed include path list. Syntax errors are ignored: -H
# still reports the headers it managed to open before the error.
set -uo pipefail
R=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
B=${BUILD_DIR:-$R/build}
L=${LGRAPH_BUILD_LOGS:-$R/.build-logs}
CXX=${CXX:-c++}
FLAGS_MAKE=${FLAGS_MAKE:-$B/src/CMakeFiles/lgraph_cypher_lib.dir/flags.make}
SERVER_FLAGS_MAKE=${SERVER_FLAGS_MAKE:-$B/src/CMakeFiles/lgraph_server_lib.dir/flags.make}
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
    total=$(grep -c '^\.+[[:space:]]' "$TMP" || true)
    unique=$(sed -n 's/^\.+[[:space:]]*//p' "$TMP" | LC_ALL=C sort -u | wc -l | tr -d ' ')
    if [ "$total" -eq 0 ]; then
        echo "header-counts: no -H header lines for $src" >&2
    fi
    printf 'headers\t%s\t%s\ttotal=%s\tunique=%s\n' \
        "$target" "$src" "$total" "$unique" >> "$OUT"
done
rm -f "$TMP"
echo "header counts written to $OUT"
