TESTS_DEB := pkg-somefiles

include ../Test.mk

DEB_FILES_COUNT = $(shell dpkg-deb -c pkg-somefiles.deb | wc -l )

TEST_CASES += test-no-filter
TEST_CASES += test-no-doc-sub
TEST_CASES += test-no-doc-all
TEST_CASES += test-no-doc-except-copyright
TEST_CASES += test-no-doc-except-copyright-subdir
TEST_CASES += test-no-doc-except-copyright-and-readme
TEST_CASES += test-include-only
TEST_CASES += test-same-include-exclude
TEST_CASES += test-upgrade test-help

test-case: $(TEST_CASES)

test-clean:
	$(DPKG_PURGE) pkg-somefiles

test-no-filter:
	# no filter, should have all files
	$(DPKG_INSTALL) pkg-somefiles.deb
	test "`$(DPKG_QUERY) -L pkg-somefiles | wc -l`" = $(DEB_FILES_COUNT)
	$(DPKG_PURGE) pkg-somefiles

test-no-doc-sub:
	# filter out /usr/share/doc/*/*; this keeps the actual
	# /usr/share/doc/pkg-somefiles dir around
	$(DPKG_INSTALL) \
	  --path-exclude '/usr/share/doc/*/*' \
	  pkg-somefiles.deb
	test -d /usr/share/doc/pkg-somefiles
	test "`ls /usr/share/doc/pkg-somefiles`" = ""
	test -f /usr/lib/pkg-somefiles/run
	$(DPKG_PURGE) pkg-somefiles

test-no-doc-all:
	# filter out /usr/share/doc/*
	$(DPKG_INSTALL) \
	  --path-exclude '/usr/share/doc/*' \
	  pkg-somefiles.deb
	! test -d /usr/share/doc/pkg-somefiles
	test -f /usr/lib/pkg-somefiles/run
	$(DPKG_PURGE) pkg-somefiles

test-no-doc-except-copyright:
	# filter out /usr/share/doc/*/* except copyright
	$(DPKG_INSTALL) \
	  --path-exclude '/usr/share/doc/*/*' \
	  --path-include '/usr/share/doc/*/copyright' \
	  pkg-somefiles.deb
	test -f /usr/share/doc/pkg-somefiles/copyright
	! test -f /usr/share/doc/pkg-somefiles/html/index.html
	! test -f /usr/share/doc/pkg-somefiles/README
	test -f /usr/lib/pkg-somefiles/run
	$(DPKG_PURGE) pkg-somefiles

test-no-doc-except-copyright-subdir:
	# prune the entire doc dir; this triggers the special case that
	# /usr/share/doc/pkg-somefiles is matched by the exclude, but still
	# needs to be created due to the following include
	$(DPKG_INSTALL) \
	  --path-exclude '/usr/share/doc/*' \
	  --path-include '/usr/share/doc/*/copyright' \
	  pkg-somefiles.deb
	test -f /usr/share/doc/pkg-somefiles/copyright
	! test -f /usr/share/doc/pkg-somefiles/html/index.html
	! test -f /usr/share/doc/pkg-somefiles/README
	test -f /usr/lib/pkg-somefiles/run
	$(DPKG_PURGE) pkg-somefiles

test-no-doc-except-copyright-and-readme:
	# two includes which revert an exclude, second of which matches
	# several subdirs with one *
	$(DPKG_INSTALL) \
	  --path-exclude '/usr/share/doc/*' \
	  --path-include '/usr/share/doc/*/copyright' \
	  --path-include '/usr*/READ*' \
	  pkg-somefiles.deb
	test -f /usr/share/doc/pkg-somefiles/copyright
	! test -f /usr/share/doc/pkg-somefiles/html/index.html
	test -f /usr/share/doc/pkg-somefiles/README
	test -f /usr/lib/pkg-somefiles/run
	$(DPKG_PURGE) pkg-somefiles

test-include-only:
	# only includes, should be a no-op and have all files
	$(DPKG_INSTALL) \
	  --path-include '/usr/*' \
	  --path-include '/usr/share/doc' \
	  --path-include '/usr/lib/*/*' \
	  pkg-somefiles.deb
	test "`$(DPKG_QUERY) -L pkg-somefiles | wc -l`" = $(DEB_FILES_COUNT)
	test -f /usr/share/doc/pkg-somefiles/copyright
	test -f /usr/share/doc/pkg-somefiles/html/index.html
	test -f /usr/lib/pkg-somefiles/run
	$(DPKG_PURGE) pkg-somefiles

test-same-include-exclude:
	# include the same things than exclude, should be a no-op and have
	# all files
	$(DPKG_INSTALL) \
	  --path-exclude '/usr/share/*' \
	  --path-include '/usr/share/*' \
	  pkg-somefiles.deb
	test "`$(DPKG_QUERY) -L pkg-somefiles | wc -l`" = $(DEB_FILES_COUNT)
	test -f /usr/share/doc/pkg-somefiles/html/index.html
	test -f /usr/lib/pkg-somefiles/run
	$(DPKG_PURGE) pkg-somefiles
	
	# now doubly so
	$(DPKG_INSTALL) \
	  --path-exclude '/usr/share/*' \
	  --path-include '/usr/share/*' \
	  --path-exclude '/usr/share/*' \
	  --path-include '/usr/share/*' \
	  pkg-somefiles.deb
	test "`$(DPKG_QUERY) -L pkg-somefiles | wc -l`" = $(DEB_FILES_COUNT)
	test -f /usr/share/doc/pkg-somefiles/html/index.html
	test -f /usr/lib/pkg-somefiles/run
	$(DPKG_PURGE) pkg-somefiles

test-upgrade:
	# files are removed/re-added on upgrades
	$(DPKG_INSTALL) pkg-somefiles.deb
	test "`$(DPKG_QUERY) -L pkg-somefiles | wc -l`" = $(DEB_FILES_COUNT)
	test -f /usr/share/doc/pkg-somefiles/copyright
	
	$(DPKG_INSTALL) \
	  --path-exclude '/usr/share/doc/*' \
	  pkg-somefiles.deb
	! test -d /usr/share/doc/pkg-somefiles
	
	$(DPKG_INSTALL) \
	  --path-exclude '/usr/share/doc/*' \
	  --path-include '/usr/share/doc/*/copyright' \
	  pkg-somefiles.deb
	test -f /usr/share/doc/pkg-somefiles/copyright
	! test -f /usr/share/doc/pkg-somefiles/README
	
	$(DPKG_INSTALL) pkg-somefiles.deb
	test "`$(DPKG_QUERY) -L pkg-somefiles | wc -l`" = $(DEB_FILES_COUNT)
	test -f /usr/share/doc/pkg-somefiles/copyright
	test -f /usr/share/doc/pkg-somefiles/README
	$(DPKG_PURGE) pkg-somefiles

# --help output explains the options
test-help:
	$(DPKG) --help | grep -q -- --path-include
	$(DPKG) --help | grep -q -- --path-exclude
