# This Makefile fragment (since dpkg 1.16.1) defines the following package
# information variables:
#
#   DEB_SOURCE: source package name.
#   DEB_VERSION: package's full version (epoch + upstream vers. + revision).
#   DEB_VERSION_EPOCH_UPSTREAM: package's version without the Debian revision.
#   DEB_VERSION_UPSTREAM_REVISION: package's version without the Debian epoch.
#   DEB_VERSION_UPSTREAM: package's upstream version.
#   DEB_DISTRIBUTION: distribution(s) listed in the current debian/changelog
#     entry.
#   DEB_TIMESTAMP: source package release date as seconds since the epoch as
#     specified in the latest debian/changelog entry (since dpkg 1.22.9),
#     although you are probably looking for SOURCE_DATE_EPOCH instead.
#
#   SOURCE_DATE_EPOCH: source release date as seconds since the epoch, as
#     specified by <https://reproducible-builds.org/specs/source-date-epoch/>
#     (since dpkg 1.18.8).
#     If it is undefined, the date of the latest changelog entry is used.
#     In both cases, the value is exported.
#
# Note:
# - Only documented variables are considered public interfaces.
# - Expects to be included from the source tree root directory.

ifndef dpkg_pkg_info_mk_included
dpkg_pkg_info_mk_included = yes

dpkg_late_eval ?= $(or $(value DPKG_CACHE_$(1)),$(eval DPKG_CACHE_$(1) := $(shell $(2)))$(value DPKG_CACHE_$(1)))

DEB_SOURCE = $(call dpkg_late_eval,DEB_SOURCE,dpkg-parsechangelog -SSource)
DEB_VERSION = $(call dpkg_late_eval,DEB_VERSION,dpkg-parsechangelog -SVersion)
DEB_VERSION_EPOCH_UPSTREAM = $(call dpkg_late_eval,DEB_VERSION_EPOCH_UPSTREAM,echo '$(DEB_VERSION)' | sed -e 's/-[^-]*$$//')
DEB_VERSION_UPSTREAM_REVISION = $(call dpkg_late_eval,DEB_VERSION_UPSTREAM_REVISION,echo '$(DEB_VERSION)' | sed -e 's/^[0-9]*://')
DEB_VERSION_UPSTREAM = $(call dpkg_late_eval,DEB_VERSION_UPSTREAM,echo '$(DEB_VERSION_EPOCH_UPSTREAM)' | sed -e 's/^[0-9]*://')
DEB_DISTRIBUTION = $(call dpkg_late_eval,DEB_DISTRIBUTION,dpkg-parsechangelog -SDistribution)
DEB_TIMESTAMP = $(call dpkg_late_eval,DEB_TIMESTAMP,dpkg-parsechangelog -STimestamp)

SOURCE_DATE_EPOCH ?= $(DEB_TIMESTAMP)
export SOURCE_DATE_EPOCH

endif # dpkg_pkg_info_mk_included
