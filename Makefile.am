## Process this file with automake to produce Makefile.in

if BUILD_DSELECT
  MAYBE_DSELECT = dselect
endif

SUBDIRS = \
	lib \
	dpkg-deb \
	dpkg-split \
	src \
	utils \
	$(MAYBE_DSELECT) \
	scripts \
	po \
	man

ACLOCAL_AMFLAGS = -I m4


dist_pkgdata_DATA = \
	cputable \
	ostable \
	abitable \
	triplettable

EXTRA_DIST = \
	.mailmap \
	ChangeLog.old \
	README.translators \
	get-version \
	run-script \
	doc/README.api \
	doc/README.feature-removal-schedule \
	doc/coding-style.txt \
	doc/frontend.txt \
	doc/lcov-epilog \
	doc/lcov-prolog \
	doc/triggers.txt \
	debian/changelog \
	debian/compat \
	debian/control \
	debian/copyright \
	debian/dpkg-dev.docs \
	debian/dpkg-dev.install \
	debian/dpkg-dev.manpages \
	debian/dpkg-dev.preinst \
	debian/dpkg-dev.lintian-overrides \
	debian/dpkg.cfg \
	debian/dpkg.cron.daily \
	debian/dpkg.docs \
	debian/dpkg.install \
	debian/dpkg.manpages \
	debian/dpkg.postinst \
	debian/dpkg.postrm \
	debian/dpkg.preinst \
	debian/dpkg.prerm \
	debian/dpkg.logrotate \
	debian/dpkg.links \
	debian/dpkg.lintian-overrides \
	debian/dselect.cfg \
	debian/dselect.docs \
	debian/dselect.install \
	debian/dselect.manpages \
	debian/dselect.preinst \
	debian/dselect.lintian-overrides \
	debian/libdpkg-dev.docs \
	debian/libdpkg-dev.install \
	debian/libdpkg-dev.lintian-overrides \
	debian/libdpkg-perl.docs \
	debian/libdpkg-perl.install \
	debian/libdpkg-perl.lintian-overrides \
	debian/source/lintian-overrides \
	debian/source/format \
	debian/source/options \
	debian/usertags \
	debian/rules \
	debian/shlibs.default \
	debian/shlibs.override

.PHONY: doc

doc: doc/Doxyfile
	$(DOXYGEN) doc/Doxyfile

doc-clean:
	rm -rf doc/html/

# Code coverage support

.PHONY: coverage coverage-clean

if COVERAGE_ENABLED
LCOV_OPTS = -q --checksum
LCOV_CAPTURE_OPTS = $(LCOV_OPTS) --no-recursion \
	-d $(top_builddir)/lib/dpkg \
	-d $(top_builddir)/src \
	-d $(top_builddir)/utils

coverage: all
	$(RM) -f *.lcov
	find -name '*.gcda' -o -name '*.gcov' | xargs $(RM) -f
	
	$(LCOV) $(LCOV_CAPTURE_OPTS) -c -o dpkg_base.lcov -i
	$(MAKE) -C lib/dpkg check
	$(MAKE) -C src check
	$(MAKE) -C utils check
	$(LCOV) $(LCOV_CAPTURE_OPTS) -c -o dpkg_test.lcov
	$(LCOV) $(LCOV_OPTS) -a dpkg_base.lcov -a dpkg_test.lcov \
	  -o dpkg_merge.lcov
	$(LCOV) $(LCOV_OPTS) -r dpkg_merge.lcov '/usr/include/*' -o dpkg.lcov
	$(LCOV_GENHTML) -q --legend --title "dpkg C code coverage" \
	  --html-prolog $(top_srcdir)/doc/lcov-prolog \
	  --html-epilog $(top_srcdir)/doc/lcov-epilog \
	  -o doc/coverage dpkg.lcov
	
	$(MAKE) -C scripts $@

coverage-clean:
	rm -rf doc/coverage/
	find -name '*.gcno' -o -name '*.gcda' -o \
	     -name '*.gcov' -o -name '*.lcov' | xargs rm -f
else
coverage:
	@echo "Need to reconfigure with --enable-coverage"

coverage-clean:
endif

.PHONY: update-po

update-po:
	$(MAKE) -C po update-po
	$(MAKE) -C scripts/po update-po
	$(MAKE) -C dselect/po update-po
	$(MAKE) -C man update-po

.PHONY: ChangeLog
DISTCLEANFILES = ChangeLog

ChangeLog:
	git log -C --stat 1.15.0.. >$@

# If we create the dist tarball from the git repository, make sure
# that we're not forgetting some files...
dist-hook:
	echo $(VERSION) >$(distdir)/.dist-version
	if [ -e .git ]; then \
		for file in `git ls-files | grep -v .gitignore`; do \
			if [ ! -e "$(distdir)/$$file" ]; then \
				echo "$$file is missing in $(distdir)" >&2 ; \
				exit 1 ; \
			fi ; \
		done ; \
	fi

clean-local: doc-clean coverage-clean
