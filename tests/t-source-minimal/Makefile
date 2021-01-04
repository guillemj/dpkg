include ../Test.mk

D := pkg-minimal_1.0

test-case:
	cd $(D); $(DPKG_BUILD_PKG) --build=full

test-clean:
	cd $(D); debian/rules clean

clean-hook:
	rm -f pkg-minimal_1.0.*
	rm -f pkg-minimal_1.0_*
