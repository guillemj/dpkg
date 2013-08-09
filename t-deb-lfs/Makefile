PKG_SFS := pkg-sfs
PKG_LFS := pkg-lfs

TESTS_DEB := $(PKG_LFS) $(PKG_SFS)

# This will test both the ar archive and the tar LFS support.
DPKG_DEB_OPTIONS = -Znone

include ../Test.mk

$(PKG_LFS)/large-file:
	dd if=/dev/zero of=$@ bs=1K count=5M

$(PKG_TFS)/small-file:
	yes | dd of=$@ bs=1K count=4

build-hook: $(PKG_LFS)/large-file $(PKG_TFS)/small-file

clean-hook:
	$(RM) $(PKG_LFS)/large-file $(PKG_TFS)/small-file

test-case:
	# test Small File Support packages
	$(DPKG_INSTALL) pkg-sfs.deb
	test "`$(PKG_STATUS) pkg-sfs`" = "install ok installed"
	test "`stat -c%s /small-file`" = "4096"
	
	# test Large File Support packages
	$(DPKG_INSTALL) pkg-lfs.deb
	test "`$(PKG_STATUS) pkg-lfs`" = "install ok installed"
	test "`stat -c%s /large-file`" = "5368709120"

test-clean:
	$(DPKG_PURGE) pkg-sfs
	$(DPKG_PURGE) pkg-lfs
