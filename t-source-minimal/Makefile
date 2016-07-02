include ../Test.mk

test-case:
	cd pkg-minimal_1.0; dpkg-buildpackage --build=full --check-command=

test-clean:
	cd pkg-minimal_1.0; debian/rules clean

clean-hook:
	rm -f pkg-minimal_1.0.*
	rm -f pkg-minimal_1.0_*
