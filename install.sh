#!/bin/bash
# Install btusb with the Qualcomm WCN785x patches (patches/6.8/series) for 6.8
# kernels as a DKMS module, plus the WCN785x firmware.
#
# Usage: sudo ./install.sh [--base <git repo> [--ref <rev>] [--path <dir>]]
set -euo pipefail

PACKAGE=qca-wcn785x-fix
VERSION=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$(dirname "$0")/dkms.conf")
SRC=/usr/src/$PACKAGE-$VERSION
REPO_DIR=$(cd "$(dirname "$0")" && pwd)
KVER=$(uname -r)
FWDIR=/lib/firmware/qca

msg()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: sudo ./install.sh [--base <git repo> [--ref <rev>] [--path <dir>]]

Without options the series is applied to Ubuntu's stock 6.8.0-138 btusb (src/6.8).

  --base <repo>  git repository (URL or local path) whose btusb.c the series
                 is applied to instead, to build it together with other btusb
                 changes. Only committed content is used.
  --ref <rev>    branch, tag or commit of that repository (default: HEAD)
  --path <dir>   directory holding btusb.c and its headers in that repository
                 (default: src/6.8 or drivers/bluetooth, whichever exists)
EOF
}

BASE=
REF=
BPATH=
while [ $# -gt 0 ]; do
    case "$1" in
        --base|--ref|--path)
            [ $# -ge 2 ] || die "$1 needs an argument"
            case "$1" in
                --base) BASE=$2 ;;
                --ref)  REF=$2 ;;
                --path) BPATH=$2 ;;
            esac
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
[ -n "$BASE" ] || [ -z "$REF$BPATH" ] || die "--ref and --path need --base"
# A local path is relative to where the script was started from.
[ -n "$BASE" ] && [ -d "$BASE" ] && BASE=$(cd "$BASE" && pwd)

[ "$(id -u)" -eq 0 ] || die "run as root: sudo ./install.sh"

case "$KVER" in
    6.8.*) ;;
    *) die "running kernel $KVER is not 6.8; this package only patches v6.8 btusb" ;;
esac

command -v dkms >/dev/null 2>&1 || \
    die "dkms is not installed. On Debian/Ubuntu: sudo apt install dkms"

[ -e "/lib/modules/$KVER/build/Makefile" ] || \
    die "kernel headers for $KVER are missing. On Debian/Ubuntu: sudo apt install linux-headers-$KVER"

# --- firmware --------------------------------------------------------------
# Only add what is missing. A file that exists with other content most likely
# came from a newer linux-firmware package; keep it.
(cd "$REPO_DIR/firmware" && sha256sum -c --quiet SHA256SUMS) || \
    die "firmware/ does not match firmware/SHA256SUMS"
mkdir -p "$FWDIR"
for f in "$REPO_DIR"/firmware/qca/*.bin; do
    dst=$FWDIR/$(basename "$f")
    if [ ! -e "$dst" ]; then
        install -m 0644 "$f" "$dst"
        msg "Installed firmware $dst"
    elif ! cmp -s "$f" "$dst"; then
        warn "$dst differs from firmware/qca (newer linux-firmware?); keeping it"
    fi
done

# --- another DKMS package building btusb ----------------------------------
# A kernel has room for one updates/dkms/btusb.ko: whichever package installs
# last (including DKMS rebuilds on kernel updates) wins.
for conf in /var/lib/dkms/*/*/source/dkms.conf; do
    [ -e "$conf" ] || continue
    other=${conf#/var/lib/dkms/}; other=${other%%/*}
    [ "$other" = "$PACKAGE" ] && continue
    grep -q '^BUILT_MODULE_NAME\[[0-9]*\]="btusb"' "$conf" || continue
    warn "DKMS package '$other' also builds btusb; this install replaces its module"
done

# --- base sources ----------------------------------------------------------
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
BASE_DIR=$REPO_DIR/src/6.8
if [ -n "$BASE" ]; then
    command -v git >/dev/null 2>&1 || die "--base needs git"
    msg "Fetching base $BASE${REF:+ ($REF)}"
    # safe.directory: a local repository owned by another user is fine here,
    # only its committed content is read.
    git -c safe.directory='*' clone -q "$BASE" "$WORK/base" || \
        die "git clone $BASE failed"
    if [ -n "$REF" ]; then
        git -C "$WORK/base" -c advice.detachedHead=false checkout -q "$REF" || \
            die "no '$REF' in $BASE"
    fi
    if [ -z "$BPATH" ]; then
        for p in src/6.8 drivers/bluetooth; do
            if [ -f "$WORK/base/$p/btusb.c" ]; then BPATH=$p; break; fi
        done
        [ -n "$BPATH" ] || \
            die "no btusb.c in src/6.8 or drivers/bluetooth of $BASE; pass --path"
    fi
    [ -f "$WORK/base/$BPATH/btusb.c" ] || die "no btusb.c in $BPATH of $BASE"
    BASE_DIR=$WORK/base/$BPATH
    BASE_DESC="$BASE $(git -C "$WORK/base" rev-parse HEAD) $BPATH"
else
    BASE_DESC="Ubuntu 6.8.0-138 stock btusb (src/6.8)"
fi
mkdir "$WORK/src" "$WORK/check"
cp "$BASE_DIR"/btusb.c "$WORK/src/"
cp "$BASE_DIR"/*.h "$WORK/src/" 2>/dev/null || true
cp "$WORK"/src/* "$WORK/check/"

# Apply the series once here, so a base it does not fit fails now and not in
# the middle of a DKMS build.
"$REPO_DIR/apply-series.sh" "$WORK/check" || die "the series does not apply to $BASE_DESC"
msg "Base: $BASE_DESC"

# --- copy source into /usr/src -------------------------------------------
msg "Installing source to $SRC"
rm -rf "$SRC"
mkdir -p "$SRC/src/6.8"
cp -a "$REPO_DIR"/dkms.conf "$REPO_DIR"/Makefile "$REPO_DIR"/prepare.sh \
      "$REPO_DIR"/apply-series.sh "$REPO_DIR"/post-install.sh "$REPO_DIR"/patches "$SRC/"
cp "$WORK"/src/* "$SRC/src/6.8/"
echo "$BASE_DESC" > "$SRC/BASE"
chmod +x "$SRC/prepare.sh" "$SRC/apply-series.sh" "$SRC/post-install.sh"

# --- (re)register with DKMS ----------------------------------------------
# Only ever touch the CURRENT kernel; builds already installed for other
# kernels must be left alone. Remove just this kernel's existing build (any
# version) so the rebuild is clean, then (re)build for $KVER only.
EXISTING=$(dkms status "$PACKAGE" -k "$KVER" 2>/dev/null | \
           sed -n "s|^$PACKAGE[/,] *\([^,: ]*\).*|\1|p" | sort -u)
for oldver in $EXISTING; do
    msg "Removing existing $PACKAGE/$oldver build for kernel $KVER"
    dkms remove -m "$PACKAGE" -v "$oldver" -k "$KVER" || true
done

msg "Registering and building $PACKAGE/$VERSION for kernel $KVER"
# add is a no-op (and harmlessly errors) if the version is already registered
# from another kernel's install; the source in /usr/src was refreshed above.
dkms add -m "$PACKAGE" -v "$VERSION" 2>/dev/null || true
dkms build -m "$PACKAGE" -v "$VERSION" -k "$KVER" || \
    die "build failed - see /var/lib/dkms/$PACKAGE/$VERSION/build/make.log"
dkms install -m "$PACKAGE" -v "$VERSION" -k "$KVER" --force

# --- verify the module actually landed in updates/dkms --------------------
# Older DKMS versions (e.g. 2.8.x) have occasionally been seen not to place
# the module into DEST_MODULE_LOCATION; fix it up explicitly if needed.
depmod "$KVER"
MODPATH=$(modinfo -k "$KVER" -F filename btusb 2>/dev/null || true)
if ! echo "$MODPATH" | grep -q "/updates/dkms/"; then
    warn "module did not resolve to updates/dkms ($MODPATH); copying manually"
    BUILT=/var/lib/dkms/$PACKAGE/$VERSION/$KVER/$(uname -m)/module
    mkdir -p "/lib/modules/$KVER/updates/dkms"
    cp "$BUILT"/btusb.ko* "/lib/modules/$KVER/updates/dkms/"
    depmod "$KVER"
    MODPATH=$(modinfo -k "$KVER" -F filename btusb)
    echo "$MODPATH" | grep -q "/updates/dkms/" || \
        die "module still resolves to $MODPATH - installation failed"
fi
msg "Module installed: $MODPATH"

# --- Secure Boot hint ------------------------------------------------------
if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
    if [ ! -e /var/lib/shim-signed/mok/MOK.priv ]; then
        warn "Secure Boot is enabled but no DKMS MOK signing key was found."
        warn "The module may be refused at load time."
    fi
fi

# --- reload the driver -----------------------------------------------------
msg "Reloading btusb (Bluetooth will briefly disconnect)"
modprobe -r btusb 2>/dev/null || warn "could not unload btusb (in use?); reboot to activate"
modprobe btusb || die "modprobe btusb failed - check 'journalctl -k'"

echo
msg "Done. Checks:"
dkms status "$PACKAGE"
echo "base: $BASE_DESC"
echo "loaded module: $(modinfo -F filename btusb)"
echo
echo "Watch the controller come up:  journalctl -kf | grep -i -e bluetooth -e qca"
