# Makefile snippet defining the following vendor-related variables:
#
# DEB_VENDOR: output of dpkg-vendor --query Vendor
# DEB_PARENT_VENDOR: output of dpkg-vendor --query Parent (can be empty)
#
# The snippet also defines a macro "dpkg_vendor_derives_from" that you can
# use to verify if the current vendor derives from another vendor with a
# simple test like this one:
# ifeq ($(call dpkg_vendor_derives_from ubuntu),yes)
#   ...
# endif

dpkg_late_eval ?= $(or $(value DPKG_CACHE_$(1)),$(eval DPKG_CACHE_$(1) := $(shell $(2)))$(value DPKG_CACHE_$(1)))

DEB_VENDOR = $(call dpkg_late_eval,DEB_VENDOR,dpkg-vendor --query Vendor)
DEB_PARENT_VENDOR = $(call dpkg_late_eval,DEB_PARENT_VENDOR,dpkg-vendor --query Parent)

dpkg_vendor_derives_from = dpkg-vendor --derives-from $(1) && echo yes || echo no
