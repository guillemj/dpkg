# This Makefile fragment (since dpkg 1.16.1) defines the following host
# variables:
#
#   ASFLAGS: flags for the host assembler (since 1.21.0).
#   CFLAGS: flags for the host C compiler.
#   CPPFLAGS: flags for the host C preprocessor.
#   CXXFLAGS: flags for the host C++ compiler.
#   OBJCFLAGS: flags for the host Objective C compiler.
#   OBJCXXFLAGS: flags for the host Objective C++ compiler.
#   DFLAGS: flags for the host D compiler.
#   FFLAGS: flags for the host Fortran 77 compiler.
#   FCFLAGS: flags for the host Fortran 9x compiler.
#   LDFLAGS: flags for the host linker.
#
# And the following variables for the build tools (since dpkg 1.22.1):
#
#   ASFLAGS_FOR_BUILD: flags for the build assembler.
#   CFLAGS_FOR_BUILD: flags for the build C compiler.
#   CPPFLAGS_FOR_BUILD: flags for the build C preprocessor.
#   CXXFLAGS_FOR_BUILD: flags for the build C++ compiler.
#   OBJCFLAGS_FOR_BUILD: flags for the build Objective C compiler.
#   OBJCXXFLAGS_FOR_BUILD: flags for the build Objective C++ compiler.
#   DFLAGS_FOR_BUILD: flags for the build D compiler.
#   FFLAGS_FOR_BUILD: flags for the build Fortran 77 compiler.
#   FCFLAGS_FOR_BUILD: flags for the build Fortran 9x compiler.
#   LDFLAGS_FOR_BUILD: flags for the build linker.
#
# You can also export them in the environment by setting
# DPKG_EXPORT_BUILDFLAGS to a non-empty value.
#

ifndef dpkg_buildflags_mk_included
dpkg_buildflags_mk_included = yes

# This list is kept in sync with the default set of flags returned
# by dpkg-buildflags.

DPKG_BUILDFLAGS_LIST := $(foreach var,\
  ASFLAGS \
  CFLAGS \
  CPPFLAGS \
  CXXFLAGS \
  OBJCFLAGS \
  OBJCXXFLAGS \
  DFLAGS \
  FFLAGS \
  FCFLAGS \
  LDFLAGS \
  ,$(var) $(var)_FOR_BUILD)

dpkg_buildflags_run = $(eval $(shell \
  $(foreach exported,\
    DEB_BUILD_OPTIONS \
    DEB_BUILD_MAINT_OPTIONS \
    DEB_BUILD_PATH \
    $(foreach flag,$(DPKG_BUILDFLAGS_LIST),\
      $(foreach operation,SET STRIP APPEND PREPEND,\
        DEB_$(flag)_MAINT_$(operation))),\
    $(if $(value $(exported)),\
      $(exported)="$(value $(exported))"))\
  dpkg-buildflags | sed 's/\([^=]*\)\(.*\)/$$(eval \1:\2)/'))

ifdef DPKG_EXPORT_BUILDFLAGS
  # We need to compute the values right now.
  $(dpkg_buildflags_run)
  export $(DPKG_BUILDFLAGS_LIST)
else
  dpkg_lazy_eval ?= $(eval $(1) = $(2)$$($(1)))
  $(foreach v,$(DPKG_BUILDFLAGS_LIST),\
    $(call dpkg_lazy_eval,$(v),$$(dpkg_buildflags_run)))
endif

endif # dpkg_buildflags_mk_included
