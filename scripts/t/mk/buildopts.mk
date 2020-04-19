include $(srcdir)/mk/buildopts.mk

test:
	test "$(DEB_BUILD_OPTION_PARALLEL)" = "$(TEST_DEB_BUILD_OPTION_PARALLEL)"
