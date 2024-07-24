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
#   DEB_TIMESTAMP: source package relase date as seconds since the epoch as
#     specified in the latest debian/changelog entry (since dpkg 1.22.9),
#     although you are probably looking for SOURCE_DATE_EPOCH instead.
#
#   SOURCE_DATE_EPOCH: source release date as seconds since the epoch, as
#     specified by <https://reproducible-builds.org/specs/source-date-epoch/>
#     (since dpkg 1.18.8).
#     If it is undefined, the date of the latest changelog entry is used.
#     In both cases, the value is exported.

ifndef dpkg_pkg_info_mk_included
dpkg_pkg_info_mk_included = yes

dpkg_parsechangelog_run = $(eval $(shell dpkg-parsechangelog | sed -n '\
  s/^Distribution: \(.*\)/$$(eval DEB_DISTRIBUTION:=\1)/p;\
  s/^Source: \(.*\)/$$(eval DEB_SOURCE:=\1)/p;\
  s/^Version: \([0-9]*:\)\{0,1\}\([^-]*\)\(\(.*\)-[^-]*\)\{0,1\}$$/\
    $$(eval DEB_VERSION:=\1\2\3)\
    $$(eval DEB_VERSION_EPOCH_UPSTREAM:=\1\2\4)\
    $$(eval DEB_VERSION_UPSTREAM_REVISION:=\2\3)\
    $$(eval DEB_VERSION_UPSTREAM:=\2\4)/p;\
  s/^Timestamp: \(.*\)/$$(eval DEB_TIMESTAMP:=\1)/p'))

# Compute all the values in one go.
$(dpkg_parsechangelog_run)

SOURCE_DATE_EPOCH ?= $(DEB_TIMESTAMP)
export SOURCE_DATE_EPOCH

endif # dpkg_pkg_info_mk_included
