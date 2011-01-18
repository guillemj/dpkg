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

test-clean:
	$(DPKG_QUERY) -W | grep ^pkg-ma- | (while read pkg ver; do \
	    $(DPKG_PURGE) $$pkg; \
	done)
	rm -f $(DPKG_ADMINDIR)/arch
