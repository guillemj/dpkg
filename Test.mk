#
# Dpkg functional testsuite (kind of)
#
# Copyright © 2008-2012 Guillem Jover <guillem@debian.org>
#

-include ../.pkg-tests.conf

## Feature checks setup ##

include ../Feature.mk

## Test case support ##

ifneq (,$(filter debug,$(DPKG_TESTSUITE_OPTIONS)))
DPKG_MAINTSCRIPT_DEBUG = DPKG_DEBUG=1
endif

DPKG_PATH := $(PATH):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ifdef DPKG_BUILDTREE
DPKG_PATH := $(DPKG_BUILDTREE)/dpkg-deb:$(DPKG_BUILDTREE)/dpkg-split:$(DPKG_BUILDTREE)/src:$(DPKG_BUILDTREE)/utils:$(DPKG_PATH)
endif

DPKG_ENV = \
  PATH=$(DPKG_PATH) \
  LD_PRELOAD="$(LD_PRELOAD)" \
  LD_LIBRARY_PATH="$(LD_LIBRARY_PATH)" \
  $(DPKG_MAINTSCRIPT_DEBUG)

export PATH
PATH = $(DPKG_PATH)

BEROOT := sudo env $(DPKG_ENV)

DPKG_OPTIONS = --force-unsafe-io --no-debsig --log=/dev/null

ifneq (,$(filter debug,$(DPKG_TESTSUITE_OPTIONS)))
DPKG_OPTIONS += -D77777
endif

# Always use a local db (requires at least dpkg 1.16.0)
DPKG_ADMINDIR = $(CURDIR)/../dpkgdb
DPKG_COMMON_OPTIONS = --admindir=$(DPKG_ADMINDIR)
ifdef DPKG_BUILD_PKG_HAS_IGNORE_BUILTIN_BUILDDEPS
DPKG_CHECKBUILDDEPS_OPTIONS = --ignore-builtin-builddeps
else
DPKG_CHECKBUILDDEPS_OPTIONS = -d
endif
DPKG_BUILD_PKG_OPTIONS = $(DPKG_CHECKBUILDDEPS_OPTIONS) -us -uc --check-command=

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
DPKG_BUILD_PKG = dpkg-buildpackage $(DPKG_BUILD_PKG_OPTIONS)
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
	$(RM) $(DEB) $(DSC) *.diff.xz *.diff.gz *.tar.xz *.tar.gz

.PHONY: build-hook build test test-case test-clean clean-hook clean

# Most of the tests are serial in nature, as they perform package database
# changes, and the Makefile are written with that in mind. Avoid any
# surprises by explicitly disallowing parallel executions.
.NOTPARALLEL:
