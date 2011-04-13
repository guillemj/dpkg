PKG_TFS := pkg-tfs
PKG_LFS := pkg-lfs

TESTS_DEB := $(PKG_LFS) $(PKG_TFS)

# This will test both the ar archive and the tar LFS support.
DPKG_DEB_OPTIONS = -Znone

include ../Test.mk

$(PKG_LFS)/big-file:
	dd if=/dev/zero of=$@ bs=1K count=5M

$(PKG_TFS)/small-file:
	yes | dd of=$@ bs=1K count=4

build-hook: $(PKG_LFS)/big-file $(PKG_TFS)/small-file

clean-hook:
	$(RM) $(PKG_LFS)/big-file $(PKG_TFS)/small-file

test-case:
	# test Tiny File Support packages
	$(DPKG_INSTALL) pkg-tfs.deb
	test "`$(PKG_STATUS) pkg-tfs`" = "install ok installed"
	test "`stat -c%s /small-file`" = "4096"
	
	# test Large File Support packages
	$(DPKG_INSTALL) pkg-lfs.deb
	test "`$(PKG_STATUS) pkg-lfs`" = "install ok installed"
	test "`stat -c%s /big-file`" = "5368709120"

test-clean:
	$(DPKG_PURGE) pkg-tfs
	$(DPKG_PURGE) pkg-lfs
