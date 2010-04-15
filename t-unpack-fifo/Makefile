PKG := pkg-fifo

TESTS_DEB := pkg-fifo

include ../Test.mk

$(PKG)/test-fifo:
	mkfifo $@

build-hook: $(PKG)/test-fifo

clean-hook:
	rm -f $(PKG)/test-fifo

test-case:
	# test unpacking a fifo
	$(DPKG_INSTALL) pkg-fifo.deb
	test "`$(PKG_STATUS) pkg-fifo`" = "install ok installed"

test-clean:
	$(DPKG_PURGE) pkg-fifo

