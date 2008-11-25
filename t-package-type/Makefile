TESTS_DEB := pkg-package-type-use pkg-package-type-void

include ../Test.mk

test-case:
	# test presence of Package-Type field
	test -n "`$(DPKG) -f pkg-package-type-use.deb Package-Type`"
	test -z "`$(DPKG) -f pkg-package-type-void.deb Package-Type`"

