# Makefile snippet defining the following variables:
#
# DEB_SOURCE_PACKAGE: the source package name
# DEB_VERSION: the full version of the package
# DEB_VERSION_NOREV: the package's version without the Debian revision
# DEB_VERSION_NOEPOCH: the package's version without the Debian epoch
# DEB_VERSION_UPSTREAM: the package's upstream version
# DEB_DISTRIBUTION: the first distribution of the current entry in debian/changelog

dpkg_late_eval ?= $(or $(value DPKG_CACHE_$(1)),$(eval DPKG_CACHE_$(1) := $(shell $(2)))$(value DPKG_CACHE_$(1)))

DEB_SOURCE_PACKAGE = $(call dpkg_late_eval,DEB_SOURCE_PACKAGE,awk '/^Source: / { print $$2 }' debian/control)
DEB_VERSION = $(call dpkg_late_eval,DEB_VERSION,dpkg-parsechangelog | awk '/^Version: / { print $$2 }')
DEB_VERSION_NOREV = $(call dpkg_late_eval,DEB_VERSION_NOREV,echo '$(DEB_VERSION)' | sed -e 's/-[^-]*$$//')
DEB_VERSION_NOEPOCH = $(call dpkg_late_eval,DEB_VERSION_NOEPOCH,echo '$(DEB_VERSION)' | sed -e 's/^[0-9]*://')
DEB_VERSION_UPSTREAM = $(call dpkg_late_eval,DEB_VERSION_UPSTREAM,echo '$(DEB_VERSION_NOREV)' | sed -e 's/^[0-9]*://')
DEB_DISTRIBUTION = $(call dpkg_late_eval,DEB_DISTRIBUTION,dpkg-parsechangelog | awk '/^Distribution: / { print $$2 }')
