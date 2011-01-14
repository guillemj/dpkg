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

TEST_CASES += test-print-foreign-architecture

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

test-clean:
	rm -f $(DPKG_ADMINDIR)/arch
