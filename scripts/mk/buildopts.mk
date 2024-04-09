# This Makefile fragment (since dpkg 1.20.1) parses option arguments from
# DEB_BUILD_OPTIONS, and exposes these as variables.
#
# Defines the following variables:
#
#   DEB_BUILD_OPTION_PARALLEL: the argument for the parallel=N option.

ifndef dpkg_buildopts_mk_included
dpkg_buildopts_mk_included = yes

ifneq (,$(filter parallel=%,$(DEB_BUILD_OPTIONS)))
  DEB_BUILD_OPTION_PARALLEL = $(patsubst parallel=%,%,$(filter parallel=%,$(DEB_BUILD_OPTIONS)))
endif

endif # dpkg_buildopts_mk_included
