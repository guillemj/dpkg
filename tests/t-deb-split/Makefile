PKG := pkg-split

TESTS_DEB := $(PKG)

# This will make sure the generated files have controllable size.
DPKG_DEB_OPTIONS = -Znone

include ../Test.mk

$(PKG)/data-file:
	yes | dd of=$@ bs=1K count=1K

build-hook: $(PKG)/data-file

clean-hook:
	$(RM) $(PKG)/data-file
	$(RM) pkg-split-part.*.deb
	$(RM) pkg-joined.deb

test-case:
	# test splitting a package (in 3 parts: 400 KiB + 400 KiB + 224 KiB)
	$(DPKG_SPLIT) -S 400 -s pkg-split.deb pkg-split-part
	test -f pkg-split-part.1of3.deb
	test -f pkg-split-part.2of3.deb
	test -f pkg-split-part.3of3.deb
	
	# test getting information about the split parts (parsing verification)
	$(DPKG_SPLIT) -I pkg-split-part.1of3.deb
	$(DPKG_SPLIT) -I pkg-split-part.2of3.deb
	$(DPKG_SPLIT) -I pkg-split-part.3of3.deb
	
	# test joining the split parts back together
	$(DPKG_SPLIT) -o pkg-joined.deb -j pkg-split-part.*.deb
	cmp pkg-split.deb pkg-joined.deb
	
	# test installing the split parts (not in order)
	$(DPKG_INSTALL) pkg-split-part.2of3.deb
	$(DPKG_INSTALL) pkg-split-part.1of3.deb
	$(DPKG_INSTALL) pkg-split-part.3of3.deb
	$(call pkg_is_installed,pkg-split)

test-clean:
	$(DPKG_PURGE) pkg-split
