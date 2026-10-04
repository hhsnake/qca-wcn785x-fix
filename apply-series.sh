#!/bin/sh
# Apply patches/6.8/series to the btusb sources in <dir>, in order.
#
# A patch whose change <dir> already carries is skipped: Ubuntu's 6.8
# kernels contain some of them (0002, 0007, 0008), a vanilla v6.8 base
# needs all of them. A patch that neither applies nor is already present
# is an error.
#
# Usage: apply-series.sh <dir> [count]
#   count: apply only the first <count> patches of the series

set -e

dir="$1"
count="${2:-0}"
[ -n "$dir" ] || { echo "usage: apply-series.sh <dir> [count]" >&2; exit 2; }
root="$(cd "$(dirname "$0")" && pwd)"

# Patches use kernel tree paths (a/drivers/bluetooth/btusb.c): -p3 strips
# them down to the flat directory. -f keeps patch from asking questions.
n=0
while read -r p; do
    case "$p" in ''|'#'*) continue ;; esac
    n=$((n + 1))
    [ "$count" -gt 0 ] && [ "$n" -gt "$count" ] && break
    f="$root/patches/6.8/$p"
    if patch -s -f -p3 -d "$dir" --dry-run < "$f" >/dev/null 2>&1; then
        patch -s -f --no-backup-if-mismatch -p3 -d "$dir" < "$f"
        echo "qca-wcn785x-fix: applied $p"
    elif patch -s -f -R -p3 -d "$dir" --dry-run < "$f" >/dev/null 2>&1; then
        echo "qca-wcn785x-fix: already in base, skipped $p"
    else
        echo "qca-wcn785x-fix: $p does not apply" >&2
        exit 1
    fi
done < "$root/patches/6.8/series"
