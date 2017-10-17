include $(srcdir)/mk/vendor.mk

test:
	test "$(DEB_VENDOR)" = "Debian"
	test "$(DEB_PARENT_VENDOR)" = ""
