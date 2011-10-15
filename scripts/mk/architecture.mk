# This Makefile snippet defines all the DEB_HOST_* / DEB_BUILD_* variables
# that dpkg-architecture can return. Existing values of those variables
# are preserved as per policy.

dpkg_late_eval ?= $(or $(value DPKG_CACHE_$(1)),$(eval DPKG_CACHE_$(1) := $(shell $(2)))$(value DPKG_CACHE_$(1)))

dpkg_architecture_setvar = $(1) ?= $(call dpkg_late_eval,$(1),dpkg-architecture -q$(1))

$(foreach machine,BUILD HOST,\
  $(foreach var,ARCH ARCH_OS ARCH_CPU ARCH_BITS ARCH_ENDIAN GNU_CPU GNU_SYSTEM GNU_TYPE MULTIARCH,\
    $(eval $(call dpkg_architecture_setvar,DEB_$(machine)_$(var)))))
