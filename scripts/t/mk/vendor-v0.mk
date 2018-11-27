dpkg_vendor_derives_from = $(dpkg_vendor_derives_from_v0)

include $(srcdir)/mk/vendor.mk

test:
	test "$(shell $(call dpkg_vendor_derives_from,debian))" = "yes"
