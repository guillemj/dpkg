#
# Dpkg functional testsuite (kind of)
#
# Copyright © 2008-2013 Guillem Jover <guillem@debian.org>
#

-include .pkg-tests.conf

TESTS_MANUAL :=
TESTS_MANUAL += t-deb-lfs
TESTS_MANUAL += t-conffile-prompt

TESTS_FAIL :=
TESTS_FAIL += t-dir-leftover-deadlock
TESTS_FAIL += t-dir-shared-replaces-lost
TESTS_FAIL += t-disappear-depended
TESTS_FAIL += t-conffile-divert-conffile

TESTS_PASS :=
TESTS_PASS += t-db
TESTS_PASS += t-normal
TESTS_PASS += t-field-priority
TESTS_PASS += t-deb-format
TESTS_PASS += t-deb-split
TESTS_PASS += t-deb-conffiles
TESTS_PASS += t-option-dry-run
TESTS_PASS += t-option-recursive
TESTS_PASS += t-control-bogus
TESTS_PASS += t-control-no-arch
TESTS_PASS += t-unpack-symlink
TESTS_PASS += t-unpack-hardlink
TESTS_PASS += t-unpack-divert-nowarn
TESTS_PASS += t-unpack-divert-hardlink
TESTS_PASS += t-unpack-fifo
TESTS_PASS += t-unpack-device
TESTS_PASS += t-maintscript-leak
TESTS_PASS += t-filtering
TESTS_PASS += t-depends
TESTS_PASS += t-dir-leftover-parents
TESTS_PASS += t-dir-leftover-conffile
TESTS_PASS += t-disappear
TESTS_PASS += t-disappear-empty
TESTS_PASS += t-provides
TESTS_PASS += t-provides-arch-implicit
TESTS_PASS += t-provides-arch-qualified
TESTS_PASS += t-conflict
TESTS_PASS += t-conflict-provide-replace-real
TESTS_PASS += t-conflict-provide-replace-virtual
TESTS_PASS += t-conflict-provide-replace-virtual-multiarch
TESTS_PASS += t-conflict-provide-replace-interface
TESTS_PASS += t-predepends-no-triggers
TESTS_PASS += t-triggers
TESTS_PASS += t-triggers-path
TESTS_PASS += t-triggers-depends
TESTS_PASS += t-triggers-depcycle
TESTS_PASS += t-triggers-depfarcycle
TESTS_PASS += t-triggers-selfcycle
TESTS_PASS += t-triggers-cycle
TESTS_PASS += t-file-replaces
TESTS_PASS += t-file-replaces-disappear
TESTS_PASS += t-file-replaces-versioned
TESTS_PASS += t-conffile-normal
TESTS_PASS += t-conffile-obsolete
TESTS_PASS += t-conffile-orphan
TESTS_PASS += t-conffile-forcenew
TESTS_PASS += t-conffile-forceask
TESTS_PASS += t-conffile-divert-normal
TESTS_PASS += t-conffile-conflict
TESTS_PASS += t-conffile-replaces
TESTS_PASS += t-conffile-replaces-upgrade
TESTS_PASS += t-conffile-replaces-downgrade
TESTS_PASS += t-conffile-replaces-existing
TESTS_PASS += t-conffile-replaces-existing-and-upgrade
TESTS_PASS += t-conffile-replaces-disappear
TESTS_PASS += t-conffile-versioned-replaces-downgrade
TESTS_PASS += t-conffile-rename
TESTS_PASS += t-queue-process-deconf-dupe
TESTS_PASS += t-package-type
TESTS_PASS += t-symlink-dir
TESTS_PASS += t-switch-symlink-abs-to-dir
TESTS_PASS += t-switch-symlink-rel-to-dir
TESTS_PASS += t-switch-dir-to-symlink-abs
TESTS_PASS += t-switch-dir-to-symlink-rel
TESTS_PASS += t-substvars
TESTS_PASS += t-failinst-failrm
TESTS_PASS += t-dir-extension-check
TESTS_PASS += t-multiarch

ifneq (,$(filter test-all,$(DPKG_TESTSUITE_OPTIONS)))
TESTS := $(TESTS_PASS) $(TESTS_FAIL) $(TESTS_MANUAL)
else
TESTS := $(TESTS_PASS)
endif


# By default do nothing
all help::
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

