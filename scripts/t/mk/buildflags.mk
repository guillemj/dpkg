DEB_CPPFLAGS_MAINT_APPEND = -DTEST_MK=test

include $(srcdir)/mk/buildflags.mk

test:
	test "$(ASFLAGS)" = "$(TEST_ASFLAGS)"
	test "$(CFLAGS)" = "$(TEST_CFLAGS)"
	test "$(CPPFLAGS)" = "$(TEST_CPPFLAGS) -DTEST_MK=test"
	test "$(CXXFLAGS)" = "$(TEST_CXXFLAGS)"
	test "$(DFLAGS)" = "$(TEST_DFLAGS)"
	test "$(FCFLAGS)" = "$(TEST_FCFLAGS)"
	test "$(FFLAGS)" = "$(TEST_FFLAGS)"
	test "$(GCJFLAGS)" = "$(TEST_GCJFLAGS)"
	test "$(LDFLAGS)" = "$(TEST_LDFLAGS)"
	test "$(OBJCFLAGS)" = "$(TEST_OBJCFLAGS)"
	test "$(OBJCXXFLAGS)" = "$(TEST_OBJCXXFLAGS)"
