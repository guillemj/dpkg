# Copyright © 2012 Guillem Jover <guillem@debian.org>

TESTS_DEB :=

include ../Test.mk

PKG_TUPLE = LC_ALL=C $(DPKG_QUERY) -f '$${Package}:$${Architecture}:$${Version}' -W

TEST_CASES += test-dupe-multi
TEST_CASES += test-cross-single-update
TEST_CASES += test-cross-multi-update
TEST_CASES += test-bogus-single
TEST_CASES += test-bogus-dupe-same-single
TEST_CASES += test-bogus-dupe-diff-single
TEST_CASES += test-bogus-multi
TEST_CASES += test-bogus-multi-update

test-case: $(TEST_CASES)

test-dupe-multi: DPKG_ADMINDIR = db-dupe-multi
test-dupe-multi:
	$(call stdout_is,$(PKG_TUPLE),pkg-multi:amd64:1.0)

test-cross-single-update: DPKG_ADMINDIR = db-cross-single-update
test-cross-single-update:
	$(call stdout_is,$(PKG_TUPLE),pkg-single:armel:3.0)

test-cross-multi-update: DPKG_ADMINDIR = db-cross-multi-update
test-cross-multi-update:
	$(call stdout_is,$(PKG_TUPLE),pkg-multi:armel:4.0)

test-bogus-dupe-same-single: DPKG_ADMINDIR = db-bogus-dupe-same-single
test-bogus-dupe-same-single:
	$(call stderr_has,$(PKG_TUPLE),error)

test-bogus-dupe-diff-single: DPKG_ADMINDIR = db-bogus-dupe-diff-single
test-bogus-dupe-diff-single:
	$(call stderr_has,$(PKG_TUPLE),error)

test-bogus-single: DPKG_ADMINDIR = db-bogus-single
test-bogus-single:
	$(call stderr_has,$(PKG_TUPLE),error)

test-bogus-multi: DPKG_ADMINDIR = db-bogus-multi
test-bogus-multi:
	$(call stderr_has,$(PKG_TUPLE),error)

test-bogus-multi-update: DPKG_ADMINDIR = db-bogus-multi-update
test-bogus-multi-update:
	$(call stderr_has,$(PKG_TUPLE),error)
