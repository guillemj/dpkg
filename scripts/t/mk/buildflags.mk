DEB_CPPFLAGS_MAINT_APPEND = -DTEST_MK=test

include $(srcdir)/mk/buildflags.mk

test:
	test "$(CFLAGS)" = "-g -O2 -fstack-protector-strong -Wformat -Werror=format-security"
	test "$(CPPFLAGS)" = "-D_FORTIFY_SOURCE=2 -DTEST_MK=test"
	test "$(CXXFLAGS)" = "-g -O2 -fstack-protector-strong -Wformat -Werror=format-security"
	test "$(FCFLAGS)" = "-g -O2 -fstack-protector-strong"
	test "$(FFLAGS)" = "-g -O2 -fstack-protector-strong"
	test "$(GCJFLAGS)" = "-g -O2 -fstack-protector-strong"
	test "$(LDFLAGS)" = "-Wl,-z,relro"
	test "$(OBJCFLAGS)" = "-g -O2 -fstack-protector-strong -Wformat -Werror=format-security"
	test "$(OBJCXXFLAGS)" = "-g -O2 -fstack-protector-strong -Wformat -Werror=format-security"
