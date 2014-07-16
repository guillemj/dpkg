## Process this file with automake to produce Makefile.in

EXTRA_DIST =

EXTRA_DIST += $(srcdir)/package.m4

TESTSUITE_AT = $(srcdir)/testsuite.at
TESTSUITE_AT += $(srcdir)/local.at
TESTSUITE_AT += $(srcdir)/deb-format.at
TESTSUITE_AT += $(srcdir)/deb-fields.at
TESTSUITE_AT += $(srcdir)/deb-content.at
TESTSUITE_AT += $(srcdir)/deb-split.at
EXTRA_DIST += $(TESTSUITE_AT)

TESTSUITE = $(srcdir)/testsuite
EXTRA_DIST += $(TESTSUITE)

DISTCLEANFILES = atconfig

# The ":;" works around a Bash 3.2 bug when the output is not writable.
$(srcdir)/package.m4: $(top_srcdir)/configure.ac
	:;{ \
	  echo '# Signature of the current package.' && \
	  echo 'm4_define([AT_PACKAGE_NAME], [$(PACKAGE_NAME)])' && \
	  echo 'm4_define([AT_PACKAGE_TARNAME], [$(PACKAGE_TARNAME)])' && \
	  echo 'm4_define([AT_PACKAGE_VERSION], [$(PACKAGE_VERSION)])' && \
	  echo 'm4_define([AT_PACKAGE_STRING], [$(PACKAGE_STRING)])' && \
	  echo 'm4_define([AT_PACKAGE_URL], [$(PACKAGE_URL)])' && \
	  echo 'm4_define([AT_PACKAGE_BUGREPORT], [$(PACKAGE_BUGREPORT)])'; \
	} >'$(srcdir)/package.m4'

check-local: atconfig atlocal $(TESTSUITE)
	$(SHELL) '$(TESTSUITE)' $(TESTSUITEFLAGS)

installcheck-local: atconfig atlocal $(TESTSUITE)
	$(SHELL) '$(TESTSUITE)' AUTOTEST_PATH='$(bindir)' $(TESTSUITEFLAGS)

clean-local:
	test ! -f '$(TESTSUITE)' || $(SHELL) '$(TESTSUITE)' --clean

AUTOTEST = $(AUTOM4TE) --language=autotest
$(TESTSUITE): $(srcdir)/package.m4 $(TESTSUITE_AT)
	$(AUTOTEST) -I '$(srcdir)' -o $@.tmp $@.at
	mv $@.tmp $@
