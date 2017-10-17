include $(srcdir)/mk/pkg-info.mk

test:
	test "$(DEB_SOURCE)" = "source"
	test "$(DEB_VERSION)" = "1:2:3.4-5-6"
	test "$(DEB_VERSION_EPOCH_UPSTREAM)" = "1:2:3.4-5"
	test "$(DEB_VERSION_UPSTREAM_REVISION)" = "2:3.4-5-6"
	test "$(DEB_VERSION_UPSTREAM)" = "2:3.4-5"
	test "$(DEB_DISTRIBUTION)" = "suite"
