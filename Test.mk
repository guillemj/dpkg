#
# Dpkg functional testsuite (kind of)
#
# Copyright © 2008 Guillem Jover <guillem@debian.org>
#

BEROOT := sudo

ifneq (,$(filter local-db,$(DPKG_TESTSUITE_OPTIONS)))
DPKG_ADMINDIR=dpkgdb
DPKG_OPTIONS := --admindir=../$(DPKG_ADMINDIR)
endif

DPKG := dpkg $(DPKG_OPTIONS)
DPKG_INSTALL := $(BEROOT) $(DPKG) -i
DPKG_UNPACK := $(BEROOT) $(DPKG) --unpack
DPKG_CONFIGURE := $(BEROOT) $(DPKG) --configure
DPKG_REMOVE := $(BEROOT) $(DPKG) -r
DPKG_PURGE := $(BEROOT) $(DPKG) -P
DPKG_BUILD_DEB := dpkg-deb -b
DPKG_BUILD_DSC := dpkg-source -b
DPKG_QUERY := dpkg-query $(DPKG_OPTIONS)

PKG_STATUS := $(DPKG_QUERY) -f '$${Status}' -W

DEB = $(addsuffix .deb,$(TESTS_DEB))
DSC = $(addsuffix .dsc,$(TESTS_DSC))

# Common test patterns to use with $(call foo,args...)
stdout_is = test "`$(1)`" = "$(2)"
stdout_has = $(1) | grep -q "$(2)"
stderr_is = test "`$(1) 2>&1 1>/dev/null`" = "$(2)"
stderr_has = $(1) 2>&1 1>/dev/null | grep -q "$(2)"
pkg_is_installed = $(call stdout_is,$(PKG_STATUS) $(1),install ok installed)

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

