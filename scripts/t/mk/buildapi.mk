include $(srcdir)/mk/buildapi.mk

test:
	test "$(DPKG_BUILD_API)" = "0"
