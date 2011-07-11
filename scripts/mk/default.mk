# Include all the Makefiles that define variables that can be useful
# within debian/rules

dpkg_datadir = .
include $(dpkg_datadir)/architecture.mk
include $(dpkg_datadir)/buildflags.mk
include $(dpkg_datadir)/vendor.mk
