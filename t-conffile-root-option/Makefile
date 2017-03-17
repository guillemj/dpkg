TESTS_DEB := pkg-conff-a-1 pkg-conff-a-2 pkg-conff-b-1 pkg-conff-b-2

include ../Test.mk

TEST_CASES += test-conffile-move-packages-no-rootdir
TEST_CASES += test-conffile-move-packages-rootdir

test-case: $(TEST_CASES)

test-conffile-move-packages-no-rootdir:
	# Install base versions.
	$(DPKG_INSTALL) pkg-conff-a-1.deb pkg-conff-b-1.deb
	# Install update, conffile moves from a to b.
	$(DPKG_INSTALL) pkg-conff-a-2.deb pkg-conff-b-2.deb
	# Cleanup.
	-$(DPKG_PURGE) pkg-conff-b
	-$(DPKG_PURGE) pkg-conff-a

TEST_ROOT := $(CURDIR)/target

test-conffile-move-packages-rootdir:
	# Create template root dir.
	mkdir -p $(TEST_ROOT)/var/lib/dpkg/info
	mkdir -p $(TEST_ROOT)/var/lib/dpkg/updates
	touch $(TEST_ROOT)/var/lib/dpkg/status
	# Install base versions.
	$(DPKG_INSTALL) --root=$(TEST_ROOT) pkg-conff-a-1.deb pkg-conff-b-1.deb
	# Install update, conffile moves from a to b.
	$(DPKG_INSTALL) --root=$(TEST_ROOT) pkg-conff-a-2.deb pkg-conff-b-2.deb
	# Cleanup.
	-$(DPKG_PURGE) --root=$(TEST_ROOT) pkg-conff-b
	-$(DPKG_PURGE) --root=$(TEST_ROOT) pkg-conff-a

test-clean:
	-$(DPKG_PURGE) pkg-conff-a pkg-conff-b
	-$(BEROOT) rm -rf $(TEST_ROOT)
