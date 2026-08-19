#
# Dpkg functional testsuite (kind of)
#
# Copyright © 2015-2026 Guillem Jover <guillem@debian.org>
#

## Feature checks setup ##

ifneq ($(DPKG_FEATURE_CHECKS),yes)
export DPKG_FEATURE_CHECKS := yes

# XXX: once apt is fixed:
#export DPKG_HAS_CONFIGURE_WITH_IMPLICIT_TRIGGER_PENDING ?= 1

ifneq (,$(filter as-root,$(DPKG_TESTSUITE_OPTIONS)))
export DPKG_AS_ROOT = 1
endif

# Some containers, such as lxc, do not permit creating devices, as that would
# defeat the containment.
# TODO: Switch this into a dynamic feature check, once we have rewritten the
# test suite in autotest.
ifneq (,$(filter has-mknod,$(DPKG_TESTSUITE_OPTIONS)))
ifdef DPKG_AS_ROOT
export DPKG_SYS_HAS_MKNOD = 1
endif
endif

endif
