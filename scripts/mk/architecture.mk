# This Makefile fragment (since dpkg 1.16.1) defines all the DEB_HOST_* and
# DEB_BUILD_* variables that dpkg-architecture can return. Existing values
# of those variables are preserved as per policy.
# All variables are exported.

ifndef dpkg_architecture_mk_included
dpkg_architecture_mk_included = yes

dpkg_architecture_vars = \
$(foreach machine,BUILD HOST TARGET,\
  $(foreach var,ARCH ARCH_ABI ARCH_LIBC ARCH_OS ARCH_CPU ARCH_BITS ARCH_ENDIAN GNU_CPU GNU_SYSTEM GNU_TYPE MULTIARCH,\
    DEB_$(machine)_$(var)))

# dpkg-buildpackage sets all variables. Optimize this frequent case.
ifneq (,$(strip $(foreach v,$(dpkg_architecture_vars),$(if $(value $(v)),,1))))
  $(foreach line,$(subst =,?=,$(shell dpkg-architecture)),$(eval $(line)))
endif

export $(dpkg_architecture_vars)

endif # dpkg_architecture_mk_included
