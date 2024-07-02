# This Makefile fragment (since dpkg 1.16.1) defines the following
# vendor-related variables:
#
#   DEB_VENDOR: output of «dpkg-vendor --query Vendor».
#   DEB_PARENT_VENDOR: output of «dpkg-vendor --query Parent» (can be empty).
#
# This Makefile fragment also defines a set of "dpkg_vendor_derives_from"
# macros that can be used to verify if the current vendor derives from
# another vendor. The unversioned variant defaults to the v0 version if
# undefined or to the v1 version when on build API 1, otherwise it can be
# defined explicitly to one of the versions or the versioned macros can be
# used directly. The following are example usages:
#
# - dpkg_vendor_derives_from (since dpkg 1.16.1)
#
#   ifeq ($(shell $(call dpkg_vendor_derives_from,ubuntu)),yes)
#     ...
#   endif
#
# - dpkg_vendor_derives_from_v0 (since dpkg 1.19.3)
#
#   ifeq ($(shell $(call dpkg_vendor_derives_from_v0,ubuntu)),yes)
#     ...
#   endif
#
# - dpkg_vendor_derives_from_v1 (since dpkg 1.19.3)
#
#   dpkg_vendor_derives_from = $(dpkg_vendor_derives_from_v1)
#   ifeq ($(call dpkg_vendor_derives_from,ubuntu),yes)
#     ...
#   endif
#   ifeq ($(call dpkg_vendor_derives_from_v1,ubuntu),yes)
#     ...
#   endif

ifndef dpkg_vendor_mk_included
dpkg_vendor_mk_included = yes

dpkg_datadir ?= $(dir $(lastword $(MAKEFILE_LIST)))
include $(dpkg_datadir)/buildapi.mk

dpkg_lazy_eval ?= $(eval $(1) = $(2)$$($(1)))
dpkg_lazy_set ?= $(call dpkg_lazy_eval,$(1),$$(eval $(1) := $(2)))
$(call dpkg_lazy_set,DEB_VENDOR,$$(shell dpkg-vendor --query Vendor))
$(call dpkg_lazy_set,DEB_PARENT_VENDOR,$$(shell dpkg-vendor --query Parent))

dpkg_vendor_derives_from_v0 = dpkg-vendor --derives-from $(1) && echo yes || echo no
dpkg_vendor_derives_from_v1 = $(shell $(dpkg_vendor_derives_from_v0))

ifeq ($(call dpkg_build_api_ge,1),yes)
dpkg_vendor_derives_from ?= $(dpkg_vendor_derives_from_v1)
else
dpkg_vendor_derives_from ?= $(dpkg_vendor_derives_from_v0)
endif

endif # dpkg_vendor_mk_included
