#
# Dpkg functional testsuite (kind of)
#
# Copyright © 2008-2012 Guillem Jover <guillem@debian.org>
#

-include ../.pkg-tests.conf

ifneq (,$(filter debug,$(DPKG_TESTSUITE_OPTIONS)))
DPKG_MAINTSCRIPT_DEBUG = DPKG_DEBUG=1
endif

ifdef DPKG_BUILDTREE
PATH := $(DPKG_BUILDTREE)/dpkg-deb:$(DPKG_BUILDTREE)/dpkg-split:$(DPKG_BUILDTREE)/src:$(DPKG_BUILDTREE)/utils:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
BEROOT := sudo env PATH=$(PATH) $(DPKG_MAINTSCRIPT_DEBUG)
else
BEROOT := sudo env $(DPKG_MAINTSCRIPT_DEBUG)
endif

DPKG_OPTIONS = --force-unsafe-io --no-debsig

ifneq (,$(filter debug,$(DPKG_TESTSUITE_OPTIONS)))
DPKG_OPTIONS += -D77777
endif

# Always use a local db (requires at least dpkg 1.16.0)
DPKG_ADMINDIR = $(CURDIR)/../dpkgdb
DPKG_COMMON_OPTIONS = --admindir=$(DPKG_ADMINDIR)

DPKG = dpkg $(DPKG_COMMON_OPTIONS) $(DPKG_OPTIONS)
DPKG_INSTALL = $(BEROOT) $(DPKG) -i
DPKG_UNPACK = $(BEROOT) $(DPKG) --unpack
DPKG_CONFIGURE = $(BEROOT) $(DPKG) --configure
DPKG_REMOVE = $(BEROOT) $(DPKG) -r
DPKG_PURGE = $(BEROOT) $(DPKG) -P
DPKG_DEB = dpkg-deb $(DPKG_DEB_OPTIONS)
DPKG_DIVERT = dpkg-divert $(DPKG_COMMON_OPTIONS) $(DPKG_DIVERT_OPTIONS)
DPKG_DIVERT_ADD = $(BEROOT) $(DPKG_DIVERT) --add
DPKG_DIVERT_DEL = $(BEROOT) $(DPKG_DIVERT) --remove
DPKG_SPLIT = dpkg-split $(DPKG_SPLIT_OPTIONS)
DPKG_BUILD_DEB = $(DPKG_DEB) -b
DPKG_BUILD_DSC = dpkg-source -b
DPKG_QUERY = dpkg-query $(DPKG_COMMON_OPTIONS) $(DPKG_QUERY_OPTIONS)
DPKG_TRIGGER = dpkg-trigger $(DPKG_COMMON_OPTIONS) $(DPKG_TRIGGER_OPTIONS)

PKG_STATUS = $(DPKG_QUERY) -f '$${Status}' -W

DEB = $(addsuffix .deb,$(TESTS_DEB))
DSC = $(addsuffix .dsc,$(TESTS_DSC))

# Common test patterns to use with $(call foo,args...)
stdout_is = test "`$(1)`" = "$(2)"
stdout_has = $(1) | grep -qE "$(2)"
stderr_is = test "`$(1) 2>&1 1>/dev/null`" = "$(2)"
stderr_has = $(1) 2>&1 1>/dev/null | grep -qE "$(2)"
pkg_is_installed = $(call stdout_is,$(PKG_STATUS) $(1),install ok installed)
pkg_is_not_installed = $(call stdout_has,$(PKG_STATUS) $(1) 2>/dev/null, ok not-installed) || ! $(PKG_STATUS) $(1) >/dev/null 2>&1
pkg_status_is = $(call stdout_is,$(PKG_STATUS) $(1),$(2))
pkg_field_is = $(call stdout_is,$(DPKG_QUERY) -f '$${$(2)}' -W $(1),$(3))

%.deb: %
	$(DPKG_BUILD_DEB) $< $@

%.dsc: %
	$(DPKG_BUILD_DSC) $<

TEST_CASES :=

build: build-hook $(DEB) $(DSC)

test: build test-case test-clean

clean: clean-hook
	$(RM) $(DEB) $(DSC) *.diff.gz *.tar.gz

.PHONY: build-hook build test test-case test-clean clean-hook clean

# Most of the tests are serial in nature, as they perform package database
# changes, and the Makefile are written with that in mind. Avoid any
# surprises by explicitly disallowing parallel executions.
.NOTPARALLEL:
