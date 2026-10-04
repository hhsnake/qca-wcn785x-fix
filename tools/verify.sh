#!/bin/bash
# Check that src/6.8 matches provenance/6.8.manifest and that
# patches/6.8/series applies to it (or to another base).
#
# Usage: tools/verify.sh [--each] [--src <dir>]
#   --each       build the module after every patch of the series (against
#                the running kernel's headers), so each patch stands on its own
#   --src <dir>  check the series against btusb.c + headers in <dir> instead
#                of src/6.8 (e.g. csr8510-fix/src/6.8); skips the hash check
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAN="$ROOT/provenance/6.8.manifest"
KDIR=${KDIR:-/lib/modules/$(uname -r)/build}
each=0
SRCDIR=
while [ $# -gt 0 ]; do
    case "$1" in
        --each) each=1; shift ;;
        --src)  SRCDIR=$(cd "${2:?--src needs a directory}" && pwd); shift 2 ;;
        *) echo "usage: tools/verify.sh [--each] [--src <dir>]" >&2; exit 2 ;;
    esac
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- base sources ------------------------------------------------------------
if [ -z "$SRCDIR" ]; then
    SRCDIR=$ROOT/src/6.8
    bad=0
    while read -r _ sha _ dest; do
        if ! echo "$sha  $SRCDIR/$dest" | sha256sum -c --quiet - >/dev/null 2>&1; then
            echo "MISMATCH: src/6.8/$dest differs from provenance/6.8.manifest" >&2
            bad=1
        fi
    done < <(awk '$1=="file"' "$MAN")
    extra=$(cd "$SRCDIR" && ls | grep -vxF -f <(awk '$1=="file"{print $4}' "$MAN") || true)
    [ -z "$extra" ] || { echo "UNLISTED in src/6.8: $extra" >&2; bad=1; }
    [ "$bad" -eq 0 ] || exit 1
    echo "OK: src/6.8 matches provenance/6.8.manifest"
fi

stage() { # fresh copy of the base in $tmp/b
    rm -rf "$tmp/b"; mkdir "$tmp/b"
    cp "$SRCDIR"/btusb.c "$ROOT/Makefile" "$tmp/b/"
    cp "$SRCDIR"/*.h "$tmp/b/" 2>/dev/null || true
}

build() {
    local out
    if ! out=$(make -C "$KDIR" M="$tmp/b" CC=x86_64-linux-gnu-gcc-12 modules 2>&1); then
        echo "$out" >&2; return 1
    fi
    if echo "$out" | grep -q 'warning:'; then
        echo "$out" | grep 'warning:' >&2; return 1
    fi
}

# --- patch series ------------------------------------------------------------
total=$(grep -cvE '^(#|$)' "$ROOT/patches/6.8/series")
if [ "$each" -eq 1 ]; then
    for n in $(seq 1 "$total"); do
        stage
        "$ROOT/apply-series.sh" "$tmp/b" "$n" | tail -1
        build || { echo "FAILED to build with the first $n patches" >&2; exit 1; }
    done
else
    stage
    "$ROOT/apply-series.sh" "$tmp/b"
fi
echo "OK: series applies to $SRCDIR; btusb.c sha256 $(sha256sum "$tmp/b/btusb.c" | cut -d' ' -f1)"
