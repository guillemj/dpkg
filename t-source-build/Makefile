include ../Test.mk

arch := $(shell dpkg-architecture -qDEB_HOST_ARCH)

D := pkg-source-1.0
F := pkg-source_1.0

test-case:
	cd $(D); $(DPKG_BUILD_PKG) --build=full --check-command=
	mv $(F)_$(arch).changes $(F)_full.changes
	cd $(D); $(DPKG_BUILD_PKG) --build=binary --check-command=
	mv $(F)_$(arch).changes $(F)_binary.changes
	cd $(D); $(DPKG_BUILD_PKG) --build=any --check-command=
	mv $(F)_$(arch).changes $(F)_any.changes
	cd $(D); $(DPKG_BUILD_PKG) --build=all --check-command=
	cd $(D); $(DPKG_BUILD_PKG) --build=source --check-command=
	
	diff -u $(F).dsc ref/$(F).dsc
	for build in source all any binary full; do \
	  diff -u $(F)_$$build.changes ref/$(F)_$$build.changes; \
	done

test-clean:
	cd $(D); debian/rules clean

clean-hook:
	rm -f pkg-source_1.0.*
	rm -f pkg-source_1.0_*
	rm -f pkg-binary-all_1.0_*
	rm -f pkg-binary-any_1.0_*
