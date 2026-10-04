# qca-wcn785x-fix

Patched `btusb` driver for **Linux 6.8** kernels that adds support for the
**Qualcomm WCN785x** (FastConnect 7800) Bluetooth controller, USB ID
`0489:e10a`, packaged as DKMS together with the controller firmware.

Tested on Ubuntu 22.04, kernel `6.8.0-138-generic`.

## Patches

`patches/6.8/series` is applied in order on top of a btusb source tree. A patch
whose change the base already contains is skipped (`apply-series.sh`).

| # | Change | Source |
|---|---|---|
| 0001 | USB ID `0489:e10a` | `2dd1c1eee3e4` |
| 0002 | NVM selection: board ID `0xffff` treated as no board ID | `43015955795a` |
| 0003 | Custom firmware subdirectories | `a3f9f6dd047a` |
| 0004 | Allow rampatch re-download when the version matches | `82855073c108` |
| 0005 | Fail on short reads in the vendor request | `cac43d360c92` |
| 0006 | BD_ADDR byte order when setting the address | `d0b15d812688` |
| 0007 | Double free of the skb during a firmware memory dump | `c27046c98bd2`, `0317b033abcd` |
| 0008 | Trigger the coredump with `__hci_cmd_send()` | `b23d98d46d28` |
| 0009 | `0x2EDC` debug frames go to the monitor instead of ACL | equivalent of `0b00bee940cb` |
| 0010 | Log the version fields the NVM file name is built from | local |

Hashes refer to commits in torvalds/linux.

## Base

By default the series is applied to `src/6.8`: the stock btusb sources of
Ubuntu's `6.8.0-138` kernel (`linux-hwe-6.8 6.8.0-138.138~22.04.1`). Ubuntu
already carries 0002, 0007 and 0008, so they are skipped there.
`provenance/6.8.manifest` pins the sources by sha256; `tools/regen-base.sh`
rebuilds them from vanilla v6.8 and Ubuntu's source diff.

`install.sh --base` applies the series to another tree instead, for example to
build it together with other btusb changes. On a vanilla v6.8 based tree all
ten patches apply.

## Firmware

`firmware/qca`: `rampatch_usb_00190200.bin` and `nvm_usb_00190200*.bin` from
linux-firmware `225e865382d4`. Licence: `firmware/LICENSE.QualcommAtheros_ath10k`,
`firmware/NOTICE.qca`.

## Install

```bash
sudo apt install git dkms linux-headers-$(uname -r)
git clone https://github.com/hhsnake/qca-wcn785x-fix.git
cd qca-wcn785x-fix
sudo ./install.sh
```

- copies missing firmware files to `/lib/firmware/qca` (existing files are kept);
- copies the sources to `/usr/src/qca-wcn785x-fix-1.0.0`, builds and installs
  the module with DKMS for the running kernel, and reloads `btusb`;
- DKMS rebuilds the module on kernel updates within 6.8; other kernel versions
  are not built.

On another base:

```bash
sudo ./install.sh --base <git repo> [--ref <rev>] [--path <dir>]
```

| Option | Meaning |
|---|---|
| `--base <repo>` | git repository (URL or local path) whose `btusb.c` the series is applied to; only committed content is used |
| `--ref <rev>` | branch, tag or commit (default: `HEAD`) |
| `--path <dir>` | directory with `btusb.c` and its headers (default: `src/6.8` or `drivers/bluetooth`, whichever exists) |

Example, with the fake CSR8510 fix:

```bash
sudo ./install.sh --base https://github.com/hhsnake/csr8510-fix.git
```

The base used is recorded in `/usr/src/qca-wcn785x-fix-1.0.0/BASE`.

A kernel has one `updates/dkms/btusb.ko`: if another DKMS package builds
`btusb`, the package installed last provides the module.

## Uninstall

```bash
sudo ./uninstall.sh
```

Restores the stock `btusb` and removes the files in `/lib/firmware/qca` that
are identical to `firmware/qca`.

## Development

```bash
tools/verify.sh                 # src/6.8 hashes, series applies
tools/verify.sh --each          # also build after every patch
tools/verify.sh --src <dir>     # check the series against another base
make                            # build btusb.ko in the repo root, no DKMS
```

A module built with `make` has to be signed before `insmod` when Secure Boot
is enabled.
