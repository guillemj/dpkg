include ../Test.mk

build-hook:
	touch "$$(printf "pkg-newline/file\nnewline")"

clean-hook:
	rm "$$(printf "pkg-newline/file\nnewline")"

test-case:
	# cannot create package with newline
	! $(DPKG_DEB) -b pkg-newline

test-clean:
	$(RM) pkg-*.deb
