#
# Dpkg functional testsuite (kind of)
#
# Copyright © 2008-2010 Guillem Jover <guillem@debian.org>
#

TESTS := \
	t-normal \
	t-unpack-symlink \
	t-unpack-hardlink \
	t-unpack-fifo \
	t-unpack-device \
	t-disappear \
	t-disappear-empty \
	t-disappear-depended \
	t-conflict \
	t-conflict-provide-replace-real \
	t-conflict-provide-replace-virtual \
	t-file-replaces \
	t-file-replaces-disappear \
	t-conffile-obsolete \
	t-conffile-orphan \
	t-conffile-prompt \
	t-conffile-forcenew \
	t-conffile-divert-normal \
	t-conffile-divert-conffile \
	t-conffile-conflict \
	t-conffile-replaces \
	t-conffile-rename \
	t-conffile-replaces-upgrade \
	t-conffile-replaces-existing \
	t-conffile-replaces-existing-and-upgrade \
	t-conffile-replaces-disappear \
	t-package-type \
	t-symlink-dir \
	t-substvars \
	t-failinst-failrm \
	t-dir-extension-check


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

