## Process this file with automake to produce Makefile.in

man_MANS = \
	deb-buildinfo.5 \
	deb-changelog.5 \
	deb-changes.5 \
	deb-conffiles.5 \
	deb-control.5 \
	deb-src-control.5 \
	deb-src-files.5 \
	deb-src-rules.5 \
	deb-src-symbols.5 \
	deb-version.7 \
	deb-shlibs.5 \
	deb-split.5 \
	deb-substvars.5 \
	deb-symbols.5 \
	deb-postinst.5 \
	deb-postrm.5 \
	deb-preinst.5 \
	deb-prerm.5 \
	deb-triggers.5 \
	deb-old.5 \
	deb-origin.5 \
	deb-override.5 \
	deb-extra-override.5 \
	deb.5 \
	deb822.5 \
	dpkg-architecture.1 \
	dpkg-buildflags.1 \
	dpkg-buildpackage.1 \
	dpkg-checkbuilddeps.1 \
	dpkg-deb.1 \
	dpkg-distaddfile.1 \
	dpkg-divert.1 \
	dpkg-genbuildinfo.1 \
	dpkg-genchanges.1 \
	dpkg-gencontrol.1 \
	dpkg-gensymbols.1 \
	dpkg-maintscript-helper.1 \
	dpkg-mergechangelogs.1 \
	dpkg-name.1 \
	dpkg-parsechangelog.1 \
	dpkg-query.1 \
	dpkg-realpath.1 \
	dpkg-scanpackages.1 \
	dpkg-scansources.1 \
	dpkg-shlibdeps.1 \
	dpkg-source.1 \
	dpkg-split.1 \
	dpkg-statoverride.1 \
	dpkg-trigger.1 \
	dpkg-vendor.1 \
	dpkg.1 \
	dpkg.cfg.5 \
	dsc.5 \
	$(nil)

if BUILD_DSELECT
man_MANS += \
	dselect.1 \
	dselect.cfg.5
endif

if BUILD_START_STOP_DAEMON
man_MANS += \
	start-stop-daemon.8
endif

if BUILD_UPDATE_ALTERNATIVES
man_MANS += \
	update-alternatives.1
endif

CLEANFILES = $(man_MANS)

EXTRA_DIST = \
	deb-buildinfo.pod \
	deb-changelog.pod \
	deb-changes.pod \
	deb-conffiles.pod \
	deb-control.pod \
	deb-extra-override.pod \
	deb-old.pod \
	deb-origin.pod \
	deb-override.pod \
	deb-postinst.pod \
	deb-postrm.pod \
	deb-preinst.pod \
	deb-prerm.pod \
	deb-shlibs.pod \
	deb-split.pod \
	deb-src-control.pod \
	deb-src-files.pod \
	deb-src-rules.pod \
	deb-src-symbols.pod \
	deb-substvars.pod \
	deb-symbols.pod \
	deb-triggers.pod \
	deb-version.pod \
	deb.pod \
	deb822.pod \
	dpkg-architecture.pod \
	dpkg-buildflags.pod \
	dpkg-buildpackage.pod \
	dpkg-checkbuilddeps.pod \
	dpkg-deb.pod \
	dpkg-distaddfile.pod \
	dpkg-divert.pod \
	dpkg-genbuildinfo.pod \
	dpkg-genchanges.pod \
	dpkg-gencontrol.pod \
	dpkg-gensymbols.pod \
	dpkg-maintscript-helper.pod \
	dpkg-mergechangelogs.pod \
	dpkg-name.pod \
	dpkg-parsechangelog.pod \
	dpkg-query.pod \
	dpkg-realpath.pod \
	dpkg-scanpackages.pod \
	dpkg-scansources.pod \
	dpkg-shlibdeps.pod \
	dpkg-source.pod \
	dpkg-split.pod \
	dpkg-statoverride.pod \
	dpkg-trigger.pod \
	dpkg-vendor.pod \
	dpkg.pod \
	dpkg.cfg.pod \
	dsc.pod \
	dselect.pod \
	dselect.cfg.pod \
	start-stop-daemon.pod \
	update-alternatives.pod \
	utf8toman.sed \
	po/ChangeLog.old \
	po/po4a.cfg \
	po/dpkg-man.pot


# Extract the list of languages from the po4a config file.
LINGUAS_DIST = `sed -ne 's/^.*\[po4a_langs\] \(.*\)$$/\1/p' $(srcdir)/po/po4a.cfg`

# If the user has not defined it let's use the default.
LINGUAS ?= $(LINGUAS_DIST)


PO4A_V = $(PO4A_V_@AM_V@)
PO4A_V_ = $(PO4A_V_@AM_DEFAULT_V@)
PO4A_V_0 = @echo "  PO4A   $@";

PO4A_OPTS = --previous --srcdir $(srcdir) --destdir $(builddir) --no-backups \
            --porefs file --msgmerge-opt=--add-location=file \
            --package-name dpkg-man --package-version $(PACKAGE_VERSION) \
            --copyright-holder "$(PACKAGE_COPYRIGHT_HOLDER)" \
            --msgid-bugs-address $(PACKAGE_BUGREPORT)

all-local: all-local-@USE_PO4A@

all-local-no:
all-local-yes: gen-man

# We use the man-once target to guarantee there is never an empty call in
# gen-man, that starts recursing infinitely.
.PHONY: gen-man man-once

gen-man: man.stamp
	for lang in $(LINGUAS); do \
	  files=""; \
	  for man in $(man_MANS); do \
	    trans="$${man%%.[0-9]}.pod"; \
	    if [ -f $(builddir)/$$lang/$$trans ]; then \
	      files="$$files $(builddir)/$$lang/$$man"; \
	    elif [ -f $(srcdir)/$$lang/$$trans ]; then \
	      files="$$files $(srcdir)/$$lang/$$man"; \
	    fi; \
	  done; \
	  $(MAKE) mandir="$(mandir)/$$lang" man_MANS="" man-once $$files; \
	done

# FIXME: Use a stamp file until po4a supports them internally.
man.stamp:
	$(PO4A_V) $(PO4A) $(PO4A_OPTS) $(srcdir)/po/po4a.cfg
	$(AM_V_at) touch $@

clean-local: clean-local-@USE_PO4A@

clean-local-no:
clean-local-yes:
	rm -rf $(LINGUAS_DIST)
	$(AM_V_at) rm -f man.stamp

.PHONY: update-po

update-po:
	$(PO4A_V) $(PO4A) $(PO4A_OPTS) --force $(srcdir)/po/po4a.cfg

SUFFIXES = .pod .1 .5 .7 .8

POD2MAN_V = $(POD2MAN_V_@AM_V@)
POD2MAN_V_ = $(POD2MAN_V_@AM_DEFAULT_V@)
POD2MAN_V_0 = @echo "  POD2MAN $@";

POD2MAN_OPTS = --utf8 --center='dpkg suite' --release=$(PACKAGE_VERSION) \
               --date='$(PACKAGE_RELEASE_DATE)'

MANFIXUP = sed \
	-f $(srcdir)/utf8toman.sed \
	-e 's/%PACKAGE%/$(PACKAGE)/g' \
	-e 's/%VERSION%/$(PACKAGE_VERSION)/g' \
	-e 's/%RELEASE_DATE%/$(PACKAGE_RELEASE_DATE)/g' \
	-e 's:%CONFDIR%:$(sysconfdir):g' \
	-e 's:%LOGDIR%:$(logdir):g' \
	-e 's:%ADMINDIR%:$(admindir):g' \
	-e 's:%PKGDOCDIR%:$(docdir):g' \
	-e 's:%PKGCONFDIR%:$(pkgconfdir):g' \
	-e 's:%PKGLIBDIR%:$(pkglibexecdir):g' \
	-e 's:%PKGDATADIR%:$(pkgdatadir):g' \
	$(nil)

if BUILD_POD_DOC
MANGEN = $(POD2MAN_V) filename='$@'; $(POD2MAN) $(POD2MAN_OPTS) \
	  --name="$$(basename $${filename%.*})" \
	  --section="$${filename\#\#*.}" $< | \
	  $(MANFIXUP) >$@
endif

.pod.1:
	$(MANGEN)
.pod.5:
	$(MANGEN)
.pod.7:
	$(MANGEN)
.pod.8:
	$(MANGEN)

install-data-local: install-data-local-@USE_PO4A@

install-data-local-no:
install-data-local-yes:
	for lang in $(LINGUAS); do \
	  files=""; \
	  for man in $(man_MANS); do \
	    trans="$${man%%.[0-9]}.pod"; \
	    if [ -f $(builddir)/$$lang/$$trans ]; then \
	      files="$$files $(builddir)/$$lang/$$man"; \
	    elif [ -f $(srcdir)/$$lang/$$trans ]; then \
	      files="$$files $(srcdir)/$$lang/$$man"; \
	    fi; \
	  done; \
	  $(MAKE) install-man mandir="$(mandir)/$$lang" man_MANS="$$files"; \
	done

uninstall-local: uninstall-local-@USE_PO4A@

uninstall-local-no:
uninstall-local-yes:
	for lang in $(LINGUAS); do \
	  files=""; \
	  for man in $(man_MANS); do \
	    trans="$${man%%.[0-9]}.pod"; \
	    if [ -f $(builddir)/$$lang/$$trans ]; then \
	      files="$$files $(builddir)/$$lang/$$man"; \
	    elif [ -f $(srcdir)/$$lang/$$trans ]; then \
	      files="$$files $(srcdir)/$$lang/$$man"; \
	    fi; \
	  done; \
	  $(MAKE) uninstall-man mandir="$(mandir)/$$lang" man_MANS="$$files"; \
	done

dist-hook: man.stamp
	cp -p $< $(distdir)/
	for lang in $(LINGUAS_DIST); do \
	  cp -p $(srcdir)/po/$$lang.po $(distdir)/po; \
	  cp -p $(srcdir)/po/$$lang.add $(distdir)/po; \
	  $(MKDIR_P) $(distdir)/$$lang; \
	  cp -pR $(srcdir)/$$lang $(distdir)/; \
	done
