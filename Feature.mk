#
# Dpkg functional testsuite (kind of)
#
# Copyright © 2015 Guillem Jover <guillem@debian.org>
#

## Feature checks setup ##

ifneq ($(DPKG_FEATURE_CHECKS),yes)
export DPKG_FEATURE_CHECKS := yes

CHECK_VERSION = $(shell dpkg --compare-versions $(1) $(2) $(3) && echo yes)

# dpkg >= 1.16.x
ifeq ($(call CHECK_VERSION,$(DPKG_SERIES),ge,1.16.x),yes)
$(info Assuming checks for dpkg >= 1.16.x)
export DPKG_HAS_CONFIGURE_WITH_IMPLICIT_TRIGGER_PENDING ?= 1
endif

# dpkg >= 1.17.x
ifeq ($(call CHECK_VERSION,$(DPKG_SERIES),ge,1.17.x),yes)
$(info Assuming checks for dpkg >= 1.17.x)
export DPKG_HAS_STRICT_CONFFILE_PARSER ?= 1
export DPKG_HAS_STRICT_DEB_PARSER ?= 1
export DPKG_HAS_DEB_CONTROL_UNIFORM_SUPPORT ?= 1
export DPKG_HAS_VERSIONED_PROVIDES ?= 1
export DPKG_HAS_PREDEPENDS_PROVIDES ?= 1
export DPKG_HAS_TRIGGERS_AWAIT ?= 1
export DPKG_HAS_MAINTSCRIPT_SWITCH_DIR_SYMLINK ?= 1
undefine DPKG_HAS_CONFIGURE_WITH_IMPLICIT_TRIGGER_PENDING
endif

# dpkg >= 1.18.x
ifeq ($(call CHECK_VERSION,$(DPKG_SERIES),ge,1.18.x),yes)
$(info Assuming checks for dpkg >= 1.18.x)
export DPKG_HAS_TRIGPROC_DEPCHECK ?= 1
export DPKG_HAS_SAME_RUN_BIDIRECTIONAL_CONFLICTS ?= 1
export DPKG_HAS_WORKING_TRIGGERS_PENDING_UPGRADE ?= 1
# XXX: once apt is fixed:
#export DPKG_HAS_CONFIGURE_WITH_IMPLICIT_TRIGGER_PENDING ?= 1
export DPKG_HAS_STRICT_PATHNAME_WITHOUT_NEWLINES ?= 1
export DPKG_HAS_STRICT_DEB_ARCHITECTURE_FIELD ?= 1
export DPKG_HAS_REPRODUCIBLE_SOURCES ?= 1
endif

endif
