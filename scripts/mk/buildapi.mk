# This Makefile fragment (since dpkg 1.22.0) handles the build API.

ifndef dpkg_buildapi_mk_included
dpkg_buildapi_mk_included = yes

# Default API level when not set.
ifndef DPKG_BUILD_API
  dpkg_lazy_eval ?= $(eval $(1) = $(2)$$($(1)))
  dpkg_lazy_set ?= $(call dpkg_lazy_eval,$(1),$$(eval $(1) := $(2)))
  $(call dpkg_lazy_set,DPKG_BUILD_API,$$(shell dpkg-buildapi))
endif

# We could use only built-in GNU make functions, but that seems too much
# complexity given no integer operators, given that we currently have to
# fetch the build API level anyway.
dpkg_build_api_ge = $(shell test "$(DPKG_BUILD_API)" -ge "$(1)" && echo yes)

endif # dpkg_buildapi_mk_included
