#
# Dpkg functional testsuite (kind of)
#
# Copyright © 2008 Guillem Jover <guillem@debian.org>
#

BEROOT := sudo
DPKG := dpkg
DPKG_INSTALL := $(BEROOT) $(DPKG) -i
DPKG_UNPACK := $(BEROOT) $(DPKG) --unpack
DPKG_CONFIGURE := $(BEROOT) $(DPKG) --configure
DPKG_REMOVE := $(BEROOT) $(DPKG) -r
DPKG_PURGE := $(BEROOT) $(DPKG) -P
DPKG_BUILD_DEB := dpkg-deb -b
DPKG_BUILD_DSC := dpkg-source -b
DPKG_QUERY := dpkg-query

PKG_STATUS := $(DPKG_QUERY) -f '$${Status}' -W

DEB = $(addsuffix .deb,$(TESTS_DEB))
DSC = $(addsuffix .dsc,$(TESTS_DSC))

%.deb: %
	$(DPKG_BUILD_DEB) $< $@

%.dsc: %
	$(DPKG_BUILD_DSC) $<


build: build-hook $(DEB) $(DSC)

test: build test-case test-clean

clean: clean-hook
	$(RM) *.deb
	$(RM) *.dsc
	$(RM) *.tar.gz

.PHONY: build-hook build test test-case test-clean clean-hook clean

