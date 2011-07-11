# This Makefile snippet defines the following variables:
#
# CFLAGS: flags for the C compiler
# CPPFLAGS: flags for the C preprocessor
# CXXFLAGS: flags for the C++ compiler
# FFLAGS: flags for the Fortran compiler
# LDFLAGS: flags for the linker
#
# You can also export them in the environment by setting
# DPKG_EXPORT_BUILDFLAGS to a non-empty value.
#
# This list is kept in sync with the default set of flags returned
# by dpkg-buildflags.

dpkg_late_eval ?= $(or $(value DPKG_CACHE_$(1)),$(eval DPKG_CACHE_$(1) := $(shell $(2)))$(value DPKG_CACHE_$(1)))

CFLAGS = $(call dpkg_late_eval,CFLAGS,dpkg-buildflags --get CFLAGS)
CPPFLAGS = $(call dpkg_late_eval,CPPFLAGS,dpkg-buildflags --get CPPFLAGS)
CXXFLAGS = $(call dpkg_late_eval,CXXFLAGS,dpkg-buildflags --get CXXFLAGS)
FFLAGS = $(call dpkg_late_eval,FFLAGS,dpkg-buildflags --get FFLAGS)
LDFLAGS = $(call dpkg_late_eval,LDFLAGS,dpkg-buildflags --get LDFLAGS)

ifdef DPKG_EXPORT_BUILDFLAGS
  export CFLAGS CPPFLAGS CXXFLAGS FFLAGS LDFLAGS
endif
