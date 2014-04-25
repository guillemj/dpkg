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
	README.l10n \
	get-version \
	run-script \
	doc/README.api \
	doc/README.feature-removal-schedule \
	doc/coding-style.txt \
	doc/frontend.txt \
	doc/lcov-inject \
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
	debian/shlibs.override \
	$(test_cases) \
	$(test_data) \
	$(nil)

.PHONY: doc

doc: doc/Doxyfile
	$(DOXYGEN) doc/Doxyfile

doc-clean:
	rm -rf doc/html/

# Code coverage support

.PHONY: coverage coverage-clean

if COVERAGE_ENABLED
LCOV_OPTS = -q --rc geninfo_checksum=1 --rc lcov_branch_coverage=1
LCOV_CAPTURE_OPTS = $(LCOV_OPTS) --no-recursion \
	-d $(top_builddir)/lib/dpkg \
	-d $(top_builddir)/src \
	-d $(top_builddir)/utils
LCOV_INJECT = $(PERL) -i $(top_srcdir)/doc/lcov-inject

coverage: all
	: # Remove coverage data from any previous run
	rm -f *.lcov
	find -name '*.gcda' -o -name '*.gcov' | xargs rm -f

	: # Initialize data
	$(LCOV) $(LCOV_CAPTURE_OPTS) -c -o dpkg_base.lcov -i
	: # Run test cases
	$(MAKE) -C lib/dpkg check
	$(MAKE) -C src check
	$(MAKE) -C utils check
	: # Merge test coverage data
	$(LCOV) $(LCOV_CAPTURE_OPTS) -c -o dpkg_test.lcov
	$(LCOV) $(LCOV_OPTS) -a dpkg_base.lcov -a dpkg_test.lcov \
	  -o dpkg_merge.lcov
	$(LCOV) $(LCOV_OPTS) -r dpkg_merge.lcov '/usr/include/*' -o dpkg.lcov
	: # Generate reports
	$(LCOV) $(LCOV_OPTS) -l dpkg.lcov
	$(LCOV_GENHTML) $(LCOV_OPTS) \
	  --legend --title "dpkg C code coverage" \
	  -o doc/coverage dpkg.lcov

	$(MAKE) -C scripts $@

	: # XXX: Inject perl coverage into lcov index files. This is a fragile
	: # hack which might break depending on the html output generated.
	$(LCOV_INJECT) doc/coverage/index-sort-b.html
	$(LCOV_INJECT) doc/coverage/index-sort-f.html
	$(LCOV_INJECT) doc/coverage/index-sort-l.html
	$(LCOV_INJECT) doc/coverage/index.html

coverage-clean:
	rm -rf doc/coverage/
	find -name '*.gcno' -o -name '*.gcda' -o \
	     -name '*.gcov' -o -name '*.lcov' | xargs rm -f
else
coverage:
	@echo "Need to reconfigure with --enable-coverage"

coverage-clean:
endif

test_cases = \
	test/pod.t \
	test/critic.t \
	$(nil)

test_data = \
	test/critic/perlcriticrc \
	$(nil)

include $(top_srcdir)/check.am

.PHONY: update-po

update-po:
	$(MAKE) -C po update-po
	$(MAKE) -C scripts/po update-po
	$(MAKE) -C dselect/po update-po
	$(MAKE) -C man update-po

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
		git log -C --stat 1.15.0.. >$(distdir)/ChangeLog; \
	fi

clean-local: doc-clean coverage-clean check-clean
