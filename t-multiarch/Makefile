# Copyright © 2011 Linaro Limited
# Copyright © 2011 Raphaël Hertzog <hertzog@debian.org>
# Copyright © 2011-2012 Guillem Jover <guillem@debian.org>

TESTS_DEB :=

include ../Test.mk

NATIVE_ARCH := $(shell dpkg --print-architecture)
ifeq ($(NATIVE_ARCH),i386)
	FOREIGN_ARCH := amd64
else
	FOREIGN_ARCH := i386
endif

ma-setup:
	$(DPKG) --add-architecture $(FOREIGN_ARCH)

## BUILDING THE TEST PACKAGES ##

# Params are (dirname, pkgname, ver, arch, ma, dep)
# Dirname and pkgname are auto-prefixed with "pkg-ma"
define build_pkg
PKG_TO_BUILD += pkg-ma-$(1).deb

pkg-ma-$(1):: pkg-template
	[ -e pkg-ma-$(1) ] || cp -a pkg-template pkg-ma-$(1)
	sed -i -e "s/Package: .*/Package: pkg-ma-$(2)/" \
	       -e "s/Version: .*/Version: $(3)/" \
	       -e "s/Architecture: .*/Architecture: $(4)/" \
	       -e "s/Multi-Arch: .*/Multi-Arch: $(5)/" \
	       -e "s/Depends:.*/Depends: $(6)/" \
	    pkg-ma-$(1)/DEBIAN/control
	mkdir -p pkg-ma-$(1)/m-a
	echo "In file pkg-ma-$(1)" > pkg-ma-$(1)/m-a/foo-$(1)
	touch pkg-ma-$(1)

pkg-ma-$(1).deb: pkg-ma-$(1)
	$(DPKG_BUILD_DEB) --nocheck pkg-ma-$(1) pkg-ma-$(1).deb

clean-hook::
	rm -rf pkg-ma-$(1)
endef

$(foreach arch,$(NATIVE_ARCH) $(FOREIGN_ARCH),\
  $(foreach ma,same foreign allowed no,\
    $(foreach version,1.0 2.0,\
      $(eval $(call build_pkg,$(ma)_$(version)_$(arch),$(ma),$(version),$(arch),$(ma),)))))

# Arch: all done separately because M-A: same can't be Arch: all
$(foreach ma,foreign allowed no,\
  $(eval $(call build_pkg,$(ma)_1.0_all,$(ma),1.0,all,$(ma),)))

$(eval $(call build_pkg,same_1.0_all,same,1.0,all,no,))

$(foreach arch,$(NATIVE_ARCH) $(FOREIGN_ARCH),\
  $(eval $(call build_pkg,self-conflict_1.0_$(arch),self-conflict,1.0,$(arch),same,))\
  $(foreach ma,same foreign foreign-any allowed allowed-any allowed-fake no,\
    $(eval $(call build_pkg,dep-on-$(ma)_1.0_$(arch),dep-on-$(ma),1.0,$(arch),foreign,pkg-ma-$(subst -,:,$(ma)) (>= 1.0)))))

$(foreach ma,same foreign foreign-any allowed allowed-any allowed-fake no,\
  $(eval $(call build_pkg,dep-on-$(ma)_1.0_all,dep-on-$(ma),1.0,all,no,pkg-ma-$(subst -,:,$(ma)) (>= 1.0))))

build-hook: $(PKG_TO_BUILD)

## TEST CASES BELOW ##

TEST_CASES += test-print-foreign-architecture
TEST_CASES += test-build-invalid
TEST_CASES += test-install-native
TEST_CASES += test-install-foreign
TEST_CASES += test-coinstall-ma-same
TEST_CASES += test-crossgrade

test-case: $(TEST_CASES)

test-print-foreign-architecture:
	echo $(FOREIGN_ARCH) >ref-arch
	echo foobar >>ref-arch
	$(DPKG) --remove-architecture $(FOREIGN_ARCH)
	$(DPKG) --remove-architecture foobar
	$(call stdout_is,$(DPKG) --print-foreign-architectures,)
	$(DPKG) --add-architecture $(FOREIGN_ARCH)
	$(call stdout_is,$(DPKG) --print-foreign-architectures,$(FOREIGN_ARCH))
	$(DPKG) --add-architecture foobar
	$(DPKG) --print-foreign-architectures | cmp ref-arch -
	# Ensure all/any can't be addded as foreign arch
	! $(DPKG) --add-architecture all
	! $(DPKG) --add-architecture any
	# Ensure the native arch is never considered as
	$(DPKG) --add-architecture $(NATIVE_ARCH)
	$(DPKG) --print-foreign-architectures | cmp ref-arch -
	$(DPKG) --remove-architecture foobar
	rm -f ref-arch

test-build-invalid:
	# Test build of Architecture: all with Multi-Arch: same field
	! $(DPKG_BUILD_DEB) pkg-template foo.deb
	rm -f foo.deb
	# Test build of package with invalid dependency (ma-allowed:fake)
	! $(DPKG_BUILD_DEB) pkg-ma-dep-on-allowed-fake_1.0_$(NATIVE_ARCH) foo.deb
	rm -f foo.deb

test-install-native:
	$(DPKG_INSTALL) pkg-ma-same_1.0_$(NATIVE_ARCH).deb
	$(DPKG_INSTALL) pkg-ma-foreign_1.0_$(NATIVE_ARCH).deb
	$(DPKG_INSTALL) pkg-ma-allowed_1.0_$(NATIVE_ARCH).deb
	$(DPKG_INSTALL) pkg-ma-no_1.0_$(NATIVE_ARCH).deb
	$(call pkg_is_installed,pkg-ma-same:$(NATIVE_ARCH))
	$(call pkg_is_installed,pkg-ma-foreign)
	$(call pkg_is_installed,pkg-ma-allowed)
	$(call pkg_is_installed,pkg-ma-no)
	$(DPKG_PURGE) pkg-ma-same:$(NATIVE_ARCH) pkg-ma-foreign pkg-ma-allowed pkg-ma-no
	$(call pkg_is_not_installed,pkg-ma-same:$(NATIVE_ARCH))
	$(call pkg_is_not_installed,pkg-ma-foreign)
	$(call pkg_is_not_installed,pkg-ma-allowed)
	$(call pkg_is_not_installed,pkg-ma-no)

test-install-foreign:
	$(DPKG) --remove-architecture $(FOREIGN_ARCH)
	# Installation of foreign arch packages must fail by default
	! $(DPKG_INSTALL) pkg-ma-same_1.0_$(FOREIGN_ARCH).deb
	! $(DPKG_INSTALL) pkg-ma-foreign_1.0_$(FOREIGN_ARCH).deb
	! $(DPKG_INSTALL) pkg-ma-allowed_1.0_$(FOREIGN_ARCH).deb
	! $(DPKG_INSTALL) pkg-ma-no_1.0_$(FOREIGN_ARCH).deb
	# Once architecture has been added it should succeed
	$(DPKG) --add-architecture $(FOREIGN_ARCH)
	$(DPKG_INSTALL) pkg-ma-same_1.0_$(FOREIGN_ARCH).deb
	$(DPKG_INSTALL) pkg-ma-foreign_1.0_$(FOREIGN_ARCH).deb
	$(DPKG_INSTALL) pkg-ma-allowed_1.0_$(FOREIGN_ARCH).deb
	$(DPKG_INSTALL) pkg-ma-no_1.0_$(FOREIGN_ARCH).deb
	$(call pkg_is_installed,pkg-ma-same:$(FOREIGN_ARCH))
	$(call pkg_is_installed,pkg-ma-foreign:$(FOREIGN_ARCH))
	$(call pkg_is_installed,pkg-ma-allowed:$(FOREIGN_ARCH))
	$(call pkg_is_installed,pkg-ma-no:$(FOREIGN_ARCH))
	$(DPKG_PURGE) pkg-ma-same:$(FOREIGN_ARCH) pkg-ma-foreign:$(FOREIGN_ARCH) pkg-ma-allowed:$(FOREIGN_ARCH) pkg-ma-no:$(FOREIGN_ARCH)
	$(call pkg_is_not_installed,pkg-ma-same:$(FOREIGN_ARCH))
	$(call pkg_is_not_installed,pkg-ma-foreign:$(FOREIGN_ARCH))
	$(call pkg_is_not_installed,pkg-ma-allowed:$(FOREIGN_ARCH))
	$(call pkg_is_not_installed,pkg-ma-no:$(FOREIGN_ARCH))

test-coinstall-ma-same: ma-setup
	# Coinstall 2 Multi-Arch: same packages
	$(DPKG_INSTALL) pkg-ma-same_1.0_$(NATIVE_ARCH).deb
	$(DPKG_INSTALL) pkg-ma-same_1.0_$(FOREIGN_ARCH).deb
	$(call pkg_is_installed,pkg-ma-same:$(NATIVE_ARCH))
	$(call pkg_is_installed,pkg-ma-same:$(FOREIGN_ARCH))
	# Upgrade one, the other must be unconfigured
	$(DPKG_UNPACK) pkg-ma-same_2.0_$(NATIVE_ARCH).deb
	$(call stdout_is,$(PKG_STATUS) pkg-ma-same:$(NATIVE_ARCH),install ok unpacked)
	$(call stdout_is,$(PKG_STATUS) pkg-ma-same:$(FOREIGN_ARCH),install ok half-configured)
	# Configure one alone must fail
	! $(DPKG_CONFIGURE) pkg-ma-same:$(NATIVE_ARCH)
	! $(DPKG_CONFIGURE) pkg-ma-same:$(FOREIGN_ARCH)
	# Upgrade the other and it's now possible to configure them
	$(DPKG_UNPACK) pkg-ma-same_2.0_$(FOREIGN_ARCH).deb
	$(DPKG_CONFIGURE) --pending
	$(call pkg_is_installed,pkg-ma-same:$(NATIVE_ARCH))
	$(call pkg_is_installed,pkg-ma-same:$(FOREIGN_ARCH))
	$(DPKG_PURGE) pkg-ma-same:$(NATIVE_ARCH) pkg-ma-same:$(FOREIGN_ARCH)

TEST_CASES_CROSSGRADE :=
TEST_CASES_CROSSGRADE += test-crossgrade-foreign-allowed

test-crossgrade: $(TEST_CASES_CROSSGRADE)

test-crossgrade-foreign-allowed: ma-setup
	# Ensure we can cross-grade Multi-Arch: foreign/allowed
	$(DPKG_INSTALL) pkg-ma-foreign_1.0_$(NATIVE_ARCH).deb
	$(DPKG_INSTALL) pkg-ma-foreign_1.0_$(FOREIGN_ARCH).deb
	$(DPKG_INSTALL) pkg-ma-allowed_1.0_$(FOREIGN_ARCH).deb
	$(DPKG_INSTALL) pkg-ma-allowed_1.0_$(NATIVE_ARCH).deb
	$(DPKG_PURGE) pkg-ma-foreign:$(NATIVE_ARCH) pkg-ma-allowed:$(FOREIGN_ARCH)

TEST_CASES_CROSSGRADE :=
TEST_CASES_CROSSGRADE += test-crossgrade-any-all-same
TEST_CASES_CROSSGRADE += test-crossgrade-any-all-foreign
TEST_CASES_CROSSGRADE += test-crossgrade-any-all-allowed
TEST_CASES_CROSSGRADE += test-crossgrade-all-any-same
TEST_CASES_CROSSGRADE += test-crossgrade-all-any-foreign
TEST_CASES_CROSSGRADE += test-crossgrade-all-any-allowed
TEST_CASES_CROSSGRADE += test-crossgrade-same-all

test-crossgrade: $(TEST_CASES_CROSSGRADE)

test-crossgrade-any-all-%: ma-setup
	# M-A: $* / Upgrade from arch: any-native -> all
	$(DPKG_INSTALL) pkg-ma-$*_1.0_$(NATIVE_ARCH).deb
	$(DPKG_INSTALL) pkg-ma-$*_1.0_all.deb
	$(call pkg_is_installed,pkg-ma-$*:all)
	$(call pkg_is_not_installed,pkg-ma-$*:$(NATIVE_ARCH))
	$(call stdout_has,$(DPKG_QUERY) -s pkg-ma-$*,^Architecture: all)
	$(DPKG_PURGE) pkg-ma-$*
	$(call pkg_is_not_installed,pkg-ma-$*)
	# M-A: $* / Upgrade from arch: any-foreign -> all
	$(DPKG_INSTALL) pkg-ma-$*_1.0_$(FOREIGN_ARCH).deb
	$(DPKG_INSTALL) pkg-ma-$*_1.0_all.deb
	$(call pkg_is_installed,pkg-ma-$*:all)
	$(call pkg_is_not_installed,pkg-ma-$*:$(FOREIGN_ARCH))
	$(DPKG_PURGE) pkg-ma-$*

test-crossgrade-all-any-%: ma-setup
	# M-A: $* / Upgrade from arch: all -> any-native
	$(DPKG_INSTALL) pkg-ma-$*_1.0_all.deb
	$(DPKG_INSTALL) pkg-ma-$*_1.0_$(NATIVE_ARCH).deb
	$(call pkg_is_installed,pkg-ma-$*:$(NATIVE_ARCH))
	$(call pkg_is_not_installed,pkg-ma-$*:all)
	$(call stdout_has,$(DPKG_QUERY) -s pkg-ma-$*,^Architecture: $(NATIVE_ARCH))
	$(DPKG_PURGE) pkg-ma-$*:$(NATIVE_ARCH)
	$(call pkg_is_not_installed,pkg-ma-$*:all)
	$(call pkg_is_not_installed,pkg-ma-$*:$(NATIVE_ARCH))
	# M-A: $* / Upgrade from arch: all -> any-foreign
	$(DPKG_INSTALL) pkg-ma-$*_1.0_all.deb
	$(DPKG_INSTALL) pkg-ma-$*_1.0_$(FOREIGN_ARCH).deb
	$(call pkg_is_not_installed,pkg-ma-$*:all)
	$(call pkg_is_installed,pkg-ma-$*:$(FOREIGN_ARCH))
	$(DPKG_PURGE) pkg-ma-$*

test-crossgrade-same-all: ma-setup
	# Several M-A: same installed, can't upgrade to single arch all
	$(DPKG_INSTALL) pkg-ma-same_1.0_$(NATIVE_ARCH).deb
	$(DPKG_INSTALL) pkg-ma-same_1.0_$(FOREIGN_ARCH).deb
	! $(DPKG_INSTALL) pkg-ma-same_1.0_all.deb
	$(call pkg_is_installed,pkg-ma-same:$(NATIVE_ARCH))
	$(call pkg_is_installed,pkg-ma-same:$(FOREIGN_ARCH))
	$(call pkg_is_not_installed,pkg-ma-same:all)
	$(DPKG_PURGE) pkg-ma-same:$(NATIVE_ARCH) pkg-ma-same:$(FOREIGN_ARCH)

test-clean:
	$(DPKG_QUERY) -W | grep ^pkg-ma- | (while read pkg ver; do \
	    $(DPKG_PURGE) $$pkg; \
	done)
	rm -f $(DPKG_ADMINDIR)/arch
