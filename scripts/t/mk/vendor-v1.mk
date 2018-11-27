include $(srcdir)/mk/vendor.mk

dpkg_vendor_derives_from = $(dpkg_vendor_derives_from_v1)

test:
	test "$(call dpkg_vendor_derives_from,debian)" = "yes"
