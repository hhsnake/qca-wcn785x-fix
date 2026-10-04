#!/bin/sh
# DKMS PRE_BUILD hook: copy the btusb sources from src/6.8 into the build root
# and apply patches/6.8/series (Qualcomm WCN785x, 0489:e10a) on top. The kbuild
# Makefile (obj-m := btusb.o) builds the result.
#
# src/6.8 is Ubuntu's stock 6.8.0-138 btusb in this repository; in /usr/src it
# holds whatever base install.sh was given (see BASE there).
#
# Usage: prepare.sh [kernelver]
# Runs from the build/source root (DKMS runs PRE_BUILD there).

set -e

kv="${1:-$(uname -r)}"
case "$kv" in
    6.8.*) ;;
    *)
        echo "qca-wcn785x-fix: kernel $kv is not 6.8; the patches are for 6.8 only" >&2
        exit 1
        ;;
esac

root="$(cd "$(dirname "$0")" && pwd)"

cp -f "$root"/src/6.8/*.c "$root"/src/6.8/*.h "$root/"
"$root/apply-series.sh" "$root"
