# This Makefile snippet defines all the DEB_HOST_* / DEB_BUILD_* variables
# that dpkg-architecture can return. Existing values of those variables
# are preserved as per policy.

dpkg_late_eval ?= $(or $(value DPKG_CACHE_$(1)),$(eval DPKG_CACHE_$(1) := $(shell $(2)))$(value DPKG_CACHE_$(1)))

DEB_HOST_ARCH ?= $(call dpkg_late_eval,DEB_HOST_ARCH,dpkg-architecture -qDEB_HOST_ARCH)
DEB_HOST_ARCH_OS ?= $(call dpkg_late_eval,DEB_HOST_ARCH_OS,dpkg-architecture -qDEB_HOST_ARCH_OS)
DEB_HOST_ARCH_CPU ?= $(call dpkg_late_eval,DEB_HOST_ARCH_CPU,dpkg-architecture -qDEB_HOST_ARCH_CPU)
DEB_HOST_ARCH_BITS ?= $(call dpkg_late_eval,DEB_HOST_ARCH_BITS,dpkg-architecture -qDEB_HOST_ARCH_BITS)
DEB_HOST_ARCH_ENDIAN ?= $(call dpkg_late_eval,DEB_HOST_ARCH_ENDIAN,dpkg-architecture -qDEB_HOST_ARCH_ENDIAN)
DEB_HOST_GNU_CPU ?= $(call dpkg_late_eval,DEB_HOST_GNU_CPU,dpkg-architecture -qDEB_HOST_GNU_CPU)
DEB_HOST_GNU_SYSTEM ?= $(call dpkg_late_eval,DEB_HOST_GNU_SYSTEM,dpkg-architecture -qDEB_HOST_GNU_SYSTEM)
DEB_HOST_GNU_TYPE ?= $(call dpkg_late_eval,DEB_HOST_GNU_TYPE,dpkg-architecture -qDEB_HOST_GNU_TYPE)
# Disabled for squeeze-backports
#DEB_HOST_MULTIARCH ?= $(call dpkg_late_eval,DEB_HOST_MULTIARCH,dpkg-architecture -qDEB_HOST_MULTIARCH)

DEB_BUILD_ARCH ?= $(call dpkg_late_eval,DEB_BUILD_ARCH,dpkg-architecture -qDEB_BUILD_ARCH)
DEB_BUILD_ARCH_OS ?= $(call dpkg_late_eval,DEB_BUILD_ARCH_OS,dpkg-architecture -qDEB_BUILD_ARCH_OS)
DEB_BUILD_ARCH_CPU ?= $(call dpkg_late_eval,DEB_BUILD_ARCH_CPU,dpkg-architecture -qDEB_BUILD_ARCH_CPU)
DEB_BUILD_ARCH_BITS ?= $(call dpkg_late_eval,DEB_BUILD_ARCH_BITS,dpkg-architecture -qDEB_BUILD_ARCH_BITS)
DEB_BUILD_ARCH_ENDIAN ?= $(call dpkg_late_eval,DEB_BUILD_ARCH_ENDIAN,dpkg-architecture -qDEB_BUILD_ARCH_ENDIAN)
DEB_BUILD_GNU_CPU ?= $(call dpkg_late_eval,DEB_BUILD_GNU_CPU,dpkg-architecture -qDEB_BUILD_GNU_CPU)
DEB_BUILD_GNU_SYSTEM ?= $(call dpkg_late_eval,DEB_BUILD_GNU_SYSTEM,dpkg-architecture -qDEB_BUILD_GNU_SYSTEM)
DEB_BUILD_GNU_TYPE ?= $(call dpkg_late_eval,DEB_BUILD_GNU_TYPE,dpkg-architecture -qDEB_BUILD_GNU_TYPE)
# Disabled for squeeze-backports
#DEB_BUILD_MULTIARCH ?= $(call dpkg_late_eval,DEB_BUILD_MULTIARCH,dpkg-architecture -qDEB_BUILD_MULTIARCH)
