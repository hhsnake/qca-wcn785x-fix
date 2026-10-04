# kbuild part: used by DKMS after prepare.sh has copied btusb.c + headers
# into this directory and applied patches/6.8/series.
ifneq ($(KERNELRELEASE),)

obj-m := btusb.o

# Distro kernels (e.g. Ubuntu HWE) backport later HCI API changes into an older
# release, so a symbol's presence can't be inferred from the kernel version.
# Probe the target kernel's headers and let the patched btusb.c #ifdef on the
# result (bases given to install.sh --base, e.g. csr8510-fix, rely on these).
_hci_h := $(srctree)/include/net/bluetooth/hci.h
ccflags-$(shell grep -qw HCI_PRIMARY $(_hci_h) 2>/dev/null && echo y) += -DHAVE_HCI_PRIMARY
ccflags-$(shell grep -qw HCI_QUIRK_VALID_LE_STATES $(_hci_h) 2>/dev/null && echo y) += -DHAVE_HCI_QUIRK_VALID_LE_STATES
ccflags-$(shell grep -qw HCI_QUIRK_BROKEN_ERR_DATA_REPORTING $(_hci_h) 2>/dev/null && echo y) += -DHAVE_HCI_QUIRK_BROKEN_ERR_DATA_REPORTING
# HCI_QUIRK_BROKEN_READ_PAGE_SCAN_TYPE skips Read Page Scan Type, which the CSR
# clones answer with a truncated payload. Upstream since 6.14, backported into
# Ubuntu HWE 6.8 somewhere between 6.8.0-94 and 6.8.0-107.
ccflags-$(shell grep -qw HCI_QUIRK_BROKEN_READ_PAGE_SCAN_TYPE $(_hci_h) 2>/dev/null && echo y) += -DHAVE_HCI_QUIRK_BROKEN_READ_PAGE_SCAN_TYPE

# Convenience part: "make" in the repo root builds the module for the
# running kernel without DKMS (for a quick one-off test).
else

KDIR ?= /lib/modules/$(shell uname -r)/build

all:
	./prepare.sh
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
	rm -f btusb.c btbcm.h btintel.h btmrvl_drv.h btmrvl_sdio.h btmtk.h \
	      btqca.h btrtl.h h4_recv.h hci_uart.h

endif
