include $(srcdir)/mk/pkg-info.mk

TEST_DEB_SOURCE = source
TEST_DEB_VERSION = 1:2:3.4-5-6
TEST_DEB_VERSION_EPOCH_UPSTREAM = 1:2:3.4-5
TEST_DEB_VERSION_UPSTREAM_REVISION = 2:3.4-5-6
TEST_DEB_VERSION_UPSTREAM = 2:3.4-5
TEST_DEB_DISTRIBUTION = suite

test_vars := \
  DEB_SOURCE \
  DEB_VERSION \
  DEB_VERSION_EPOCH_UPSTREAM \
  DEB_VERSION_UPSTREAM_REVISION \
  DEB_VERSION_UPSTREAM \
  DEB_DISTRIBUTION \
  SOURCE_DATE_EPOCH \
  # EOL

test: $(test_vars)
	: # Test the SOURCE_DATE_EPOCH exported variable.
	test "$${SOURCE_DATE_EPOCH}" = '$(TEST_SOURCE_DATE_EPOCH)'

$(test_vars):
	: # Test the $@ Make variable.
	test '$($@)' = '$(TEST_$@)'
