include ../Test.mk

test-case:
	# extract the base members
	$(DPKG_DEB) --uniform-compression -Znone -b pkg-templ
	ar x pkg-templ.deb
	gzip -c control.tar >control.tar.gz
	gzip -c data.tar >data.tar.gz
	xz -c control.tar >control.tar.xz
	xz -c data.tar >data.tar.xz
	bzip2 -c data.tar >data.tar.bz2
	lzma -c data.tar >data.tar.lzma
	touch _ignore
	touch unknown

	# test debian-binary with 2.x versions
	cp pkg-templ.deb pkg-version-2x.deb
	echo 2.999 >debian-binary
	ar rc pkg-version-2x.deb debian-binary
	ar t pkg-version-2x.deb
	$(DPKG_DEB) -I pkg-version-2x.deb
	ar x pkg-templ.deb debian-binary

	# test debian-binary with extra lines
	cp pkg-templ.deb pkg-magic-extra.deb
	echo "extra line" >>debian-binary
	ar rc pkg-magic-extra.deb debian-binary
	ar t pkg-magic-extra.deb
	$(DPKG_DEB) -I pkg-magic-extra.deb
	ar x pkg-templ.deb debian-binary

	# test missing debian-binary member
	cp pkg-templ.deb pkg-missing-magic.deb
	ar d pkg-missing-magic.deb debian-binary
	ar t pkg-missing-magic.deb
	! $(DPKG_DEB) -I pkg-missing-magic.deb

	# test missing control member
	cp pkg-templ.deb pkg-missing-control.deb
	ar d pkg-missing-control.deb control.tar
	ar t pkg-missing-control.deb
	! $(DPKG_DEB) -I pkg-missing-control.deb

	# test missing data member
	cp pkg-templ.deb pkg-missing-data.deb
	ar d pkg-missing-data.deb data.tar
	ar t pkg-missing-data.deb
	! $(DPKG_DEB) -c pkg-missing-data.deb

	# test mixed member (index 1)
	cp pkg-templ.deb pkg-mixed-1-member.deb
	ar ra debian-binary pkg-mixed-1-member.deb unknown
	ar t pkg-mixed-1-member.deb
	! $(DPKG_DEB) -I pkg-mixed-1-member.deb

	# test mixed member (index 2)
	cp pkg-templ.deb pkg-mixed-2-member.deb
	ar ra control.tar pkg-mixed-2-member.deb unknown
	ar t pkg-mixed-2-member.deb
	! $(DPKG_DEB) -c pkg-mixed-2-member.deb

	# test swapped control and data members
	cp pkg-templ.deb pkg-swap-members.deb
	ar ma data.tar pkg-swap-members.deb control.tar
	ar t pkg-swap-members.deb
	! $(DPKG_DEB) -I pkg-swap-members.deb

	# test extra member
	cp pkg-templ.deb pkg-extra-member.deb
	ar q pkg-extra-member.deb unknown
	ar t pkg-extra-member.deb
	$(DPKG_DEB) -I pkg-extra-member.deb

	# test _ member
	cp pkg-templ.deb pkg-under-member.deb
	ar ra debian-binary pkg-under-member.deb _ignore
	ar t pkg-under-member.deb
	$(DPKG_DEB) -I pkg-under-member.deb

	# test data.tar.bad member
	dd if=/dev/zero of=data.tar.bad bs=1K count=4
	ar rc pkg-data-bad.deb debian-binary control.tar.gz data.tar.bad
	ar t pkg-data-bad.deb
	! $(DPKG_DEB) -c pkg-data-bad.deb

	# test control.tar member
	ar rc pkg-control-none.deb debian-binary control.tar data.tar
	ar t pkg-control-none.deb
	$(DPKG_DEB) -I pkg-control-none.deb

	# test control.tar.xz member
	ar rc pkg-control-xz.deb debian-binary control.tar.xz data.tar.xz
	ar t pkg-control-xz.deb
	$(DPKG_DEB) -c pkg-control-xz.deb

	# test data.tar member
	ar rc pkg-data-none.deb debian-binary control.tar.gz data.tar
	ar t pkg-data-none.deb
	$(DPKG_DEB) -c pkg-data-none.deb

	# test data.tar.gz member
	ar rc pkg-data-gz.deb debian-binary control.tar.gz data.tar.gz
	ar t pkg-data-gz.deb
	$(DPKG_DEB) -c pkg-data-gz.deb

	# test data.tar.xz member
	ar rc pkg-data-xz.deb debian-binary control.tar.gz data.tar.xz
	ar t pkg-data-xz.deb
	$(DPKG_DEB) -c pkg-data-xz.deb

	# test data.tar.bz2 member
	ar rc pkg-data-bz2.deb debian-binary control.tar.gz data.tar.bz2
	ar t pkg-data-bz2.deb
	$(DPKG_DEB) -c pkg-data-bz2.deb

	# test data.tar.lzma member
	ar rc pkg-data-lzma.deb debian-binary control.tar.gz data.tar.lzma
	ar t pkg-data-lzma.deb
	$(DPKG_DEB) -c pkg-data-lzma.deb

	# test non-uniform data.tar/control.tar member compression
	ar rc pkg-mixed-comp.deb debian-binary control.tar.xz data.tar.gz
	ar t pkg-mixed-comp.deb
	$(DPKG_DEB) -I pkg-mixed-comp.deb
	$(DPKG_DEB) -c pkg-mixed-comp.deb

test-clean:
	$(RM) _ignore unknown debian-binary control.tar* data.tar*
	$(RM) pkg-*.deb
