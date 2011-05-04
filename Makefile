#
# Dpkg functional testsuite (kind of)
#
# Copyright © 2008-2010 Guillem Jover <guillem@debian.org>
#

-include .pkg-tests.conf

TESTS_MANUAL := \
	t-lfs \
	t-conffile-prompt \

TESTS_FAIL := \
	t-disappear-depended \
	t-conffile-divert-conffile \
	t-conffile-replaces-upgrade \
	t-conffile-replaces-existing-and-upgrade \

TESTS_PASS := \
	t-normal \
	t-field-priority \
	t-split \
	t-option-dry-run \
	t-option-recursive \
	t-control-bogus \
	t-control-no-arch \
	t-unpack-symlink \
	t-unpack-hardlink \
	t-unpack-divert-hardlink \
	t-unpack-fifo \
	t-unpack-device \
	t-filtering \
	t-depends \
	t-depends-versioned \
	t-depends-provides \
	t-disappear \
	t-disappear-empty \
	t-conflict \
	t-conflict-provide-replace-real \
	t-conflict-provide-replace-virtual \
	t-conflict-provide-replace-interface \
	t-file-replaces \
	t-file-replaces-disappear \
	t-conffile-obsolete \
	t-conffile-orphan \
	t-conffile-forcenew \
	t-conffile-forceask \
	t-conffile-divert-normal \
	t-conffile-conflict \
	t-conffile-replaces \
	t-conffile-replaces-downgrade \
	t-conffile-replaces-existing \
	t-conffile-replaces-disappear \
	t-conffile-versioned-replaces-downgrade \
	t-conffile-rename \
	t-package-type \
	t-symlink-dir \
	t-substvars \
	t-failinst-failrm \
	t-dir-extension-check

ifneq (,$(filter test-all,$(DPKG_TESTSUITE_OPTIONS)))
TESTS := $(TESTS_PASS) $(TESTS_FAIL) $(TESTS_MANUAL)
else
TESTS := $(TESTS_PASS)
endif


# By default do nothing
all::
	@echo "Run 'make test' to run all the tests"
	@echo "Run 'make <test-id>-test' to run a specifict test"
	@echo "Run 'make clean' to remove all intermediary files"
	@echo ""
	@echo "The available tests are: $(TESTS)"

build_targets = $(addsuffix -build,$(TESTS))

build:: $(build_targets)
$(build_targets)::
	$(MAKE) -C $(subst -build,,$@) build

.PHONY: build $(build_targets)


test_targets = $(addsuffix -test,$(TESTS))

test:: $(test_targets)
$(test_targets)::
	$(MAKE) -C $(subst -test,,$@) test

.PHONY: test $(test_targets)


test_clean_targets = $(addsuffix -test-clean,$(TESTS))

test-clean:: $(test_clean_targets)
$(test_clean_targets)::
	$(MAKE) -C $(subst -test-clean,,$@) test-clean

.PHONY: test-clean $(test_clean_targets)


clean_targets = $(addsuffix -clean,$(TESTS))

clean:: $(clean_targets)
$(clean_targets)::
	$(MAKE) -C $(subst -clean,,$@) clean

.PHONY: clean $(clean_targets)

