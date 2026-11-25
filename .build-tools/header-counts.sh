#!/bin/bash
# Optional, opt-in header-count sampler. It is never called by any build.
#
# Usage:
#   .build-tools/header-counts.sh
#   LGRAPH_BUILD_LOGS=/path/to/logs .build-tools/header-counts.sh
#
# Runs `c++ -H -fsyntax-only` on three representative translation units and
# writes the number of headers each one pulls in to
# $LGRAPH_BUILD_LOGS/header-counts.txt. Syntax errors are expected when the
# host lacks the container's dependencies; they are ignored because -H still
# reports the header closure.
set -uo pipefail
R=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
L=${LGRAPH_BUILD_LOGS:-$R/.build-logs}
CXX=${CXX:-c++}
mkdir -p "$L"
OUT="$L/header-counts.txt"
TMP=$(mktemp)

DEFS="-DLGRAPH_USE_MOCK_KV=0 -DOPENSSL_NO_KRB5=1 -D__STDC_FORMAT_MACROS -DGFLAGS_NS= -D__const__="
PYINC=$(python3-config --includes 2>/dev/null || true)
INCS="-I$R/src/cypher -I$R/src -I$R/include -I$R/deps -I$R/deps/geax-front-end/include -isystem $R/deps/install/include -isystem $R/deps/install/include/antlr4-runtime $PYINC"

: > "$OUT"
for entry in \
    "lgraph_cypher_lib:src/cypher/execution_plan/execution_plan.cpp" \
    "lgraph_server_lib:src/restful/server/rest_server.cpp" \
    "lgraph_server_lib:src/http/http_server.cpp"; do
    target=${entry%%:*}
    src=${entry#*:}
    "$CXX" -std=gnu++17 -H -fsyntax-only $DEFS $INCS "$R/$src" \
        >/dev/null 2>"$TMP" || true
    total=$(grep -c '^\.+ ' "$TMP" || true)
    unique=$(sed -n 's/^\.+ //p' "$TMP" | sort -u | wc -l | tr -d ' ')
    printf 'headers\t%s\t%s\ttotal=%s\tunique=%s\n' \
        "$target" "$src" "$total" "$unique" >> "$OUT"
done
rm -f "$TMP"
echo "header counts written to $OUT"
