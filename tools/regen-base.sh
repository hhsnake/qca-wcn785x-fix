#!/bin/bash
# Rebuild src/6.8 (Ubuntu 6.8.0-138 stock btusb sources) from the pins in
# provenance/6.8.manifest: vanilla v6.8 files + the drivers/bluetooth hunks of
# Ubuntu's linux-hwe-6.8 diff.gz. Every download and the result are checked
# against the manifest's sha256.
#
# Usage: tools/regen-base.sh [dest_dir]   (default: src/6.8)
#   Set KERNEL_GIT=/path/to/linux(.git) to read vanilla files from a local clone.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAN="$ROOT/provenance/6.8.manifest"
DEST=${1:-$ROOT/src/6.8}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

commit=$(awk '$1=="commit"{print $2}' "$MAN")
mapfile -t mirrors < <(awk '$1=="mirror"{print $2}' "$MAN")
mapfile -t umirrors < <(awk '$1=="ubuntu-mirror"{print $2}' "$MAN")
read -r _ dsha dfile < <(awk '$1=="ubuntu-diff"' "$MAN")

check() { echo "$1  $2" | sha256sum -c --quiet - >/dev/null 2>&1; }

fetch_vanilla() { # $1=kernel path, $2=dest file
    local url
    if [ -n "${KERNEL_GIT:-}" ] && \
       git -C "$KERNEL_GIT" cat-file -e "$commit:$1" 2>/dev/null; then
        git -C "$KERNEL_GIT" show "$commit:$1" > "$2"; return 0
    fi
    for m in "${mirrors[@]}"; do
        url=${m//\{commit\}/$commit}; url=${url//\{path\}/$1}
        curl -fsSL "$url" -o "$2" 2>/dev/null && return 0
    done
    return 1
}

# --- vanilla v6.8 ------------------------------------------------------------
mkdir -p "$work/src"
while read -r _ sha path; do
    dest=$(basename "$path")
    fetch_vanilla "$path" "$work/src/$dest" || { echo "fetch failed: $path" >&2; exit 1; }
    check "$sha" "$work/src/$dest" || { echo "sha256 mismatch: $path @ v6.8" >&2; exit 1; }
done < <(awk '$1=="vanilla"' "$MAN")

# --- Ubuntu diff.gz ----------------------------------------------------------
ok=0
for m in "${umirrors[@]}"; do
    url=${m//\{file\}/${dfile//\~/%7e}}
    if curl -fsSL "$url" -o "$work/$dfile" 2>/dev/null && check "$dsha" "$work/$dfile"; then
        ok=1; break
    fi
done
[ "$ok" -eq 1 ] || { echo "could not fetch $dfile with sha256 $dsha" >&2; exit 1; }

# Keep only the hunks for files we vendor, then apply them.
want=$(awk '$1=="vanilla"{n=split($3,a,"/"); print a[n]}' "$MAN" | tr '\n' ' ')
zcat "$work/$dfile" | awk -v want=" $want" '
    /^diff /  { keep = 0 }
    /^--- /   { n = split($2, a, "/"); keep = (a[n-2] == "drivers" && a[n-1] == "bluetooth" && index(want, " " a[n] " ") > 0) }
    keep' > "$work/bt.diff"
patch -s -p3 -d "$work/src" < "$work/bt.diff"

# --- result ------------------------------------------------------------------
while read -r _ sha _ dest; do
    check "$sha" "$work/src/$dest" || { echo "result sha256 mismatch: $dest" >&2; exit 1; }
done < <(awk '$1=="file"' "$MAN")

mkdir -p "$DEST"
cp "$work"/src/* "$DEST/"
echo "OK: $DEST rebuilt from v6.8 + $dfile"
