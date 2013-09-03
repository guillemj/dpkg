## Process this file with automake to produce Makefile.in

dist_man_MANS = \
	deb-control.5 \
	deb-src-control.5 \
	deb-version.5 \
	deb-shlibs.5 \
	deb-split.5 \
	deb-substvars.5 \
	deb-symbols.5 \
	deb-triggers.5 \
	deb-old.5 \
	deb-origin.5 \
	deb-override.5 \
	deb-extra-override.5 \
	deb.5 \
	dpkg-architecture.1 \
	dpkg-buildflags.1 \
	dpkg-buildpackage.1 \
	dpkg-checkbuilddeps.1 \
	dpkg-deb.1 \
	dpkg-distaddfile.1 \
	dpkg-divert.8 \
	dpkg-genchanges.1 \
	dpkg-gencontrol.1 \
	dpkg-gensymbols.1 \
	dpkg-maintscript-helper.1 \
	dpkg-mergechangelogs.1 \
	dpkg-name.1 \
	dpkg-parsechangelog.1 \
	dpkg-query.1 \
	dpkg-scanpackages.1 \
	dpkg-scansources.1 \
	dpkg-shlibdeps.1 \
	dpkg-source.1 \
	dpkg-split.1 \
	dpkg-statoverride.8 \
	dpkg-trigger.1 \
	dpkg-vendor.1 \
	dpkg.1 \
	dpkg.cfg.5

if BUILD_DSELECT
dist_man_MANS += \
	dselect.1 \
	dselect.cfg.5
endif

if BUILD_START_STOP_DAEMON
dist_man_MANS += \
	start-stop-daemon.8
endif

if BUILD_UPDATE_ALTERNATIVES
dist_man_MANS += \
	update-alternatives.8
endif

EXTRA_DIST = \
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

PO4A_OPTS = --previous --srcdir $(srcdir) --destdir $(CURDIR) --no-backups \
            --package-name dpkg-man --package-version $(PACKAGE_VERSION) \
            --msgid-bugs-address $(PACKAGE_BUGREPORT)

all-local: all-local-@USE_PO4A@

all-local-no:
all-local-yes: man.stamp

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

install-data-local: install-data-local-@USE_PO4A@

install-data-local-no:
install-data-local-yes:
	for lang in $(LINGUAS); do \
		files=""; \
		for trans in $(dist_man_MANS); do \
			if [ -f $(CURDIR)/$$lang/$$trans ]; then \
				files="$$files $(CURDIR)/$$lang/$$trans"; \
			elif [ -f $(srcdir)/$$lang/$$trans ]; then \
				files="$$files $(srcdir)/$$lang/$$trans"; \
			fi; \
		done; \
		$(MAKE) install-man \
			mandir="$(mandir)/$$lang" \
			man_MANS="" \
			dist_man_MANS="$$files"; \
	done

uninstall-local: uninstall-local-@USE_PO4A@

uninstall-local-no:
uninstall-local-yes:
	for lang in $(LINGUAS); do \
		files=""; \
		for trans in $(dist_man_MANS); do \
			if [ -f $(CURDIR)/$$lang/$$trans ]; then \
				files="$$files $(CURDIR)/$$lang/$$trans"; \
			elif [ -f $(srcdir)/$$lang/$$trans ]; then \
				files="$$files $(srcdir)/$$lang/$$trans"; \
			fi; \
		done; \
		$(MAKE) uninstall-man \
			mandir="$(mandir)/$$lang" \
			man_MANS="" \
			dist_man_MANS="$$files"; \
	done

dist-hook: man.stamp
	cp $(srcdir)/man.stamp $(distdir)/
	for lang in $(LINGUAS_DIST); do \
		cp $(srcdir)/po/$$lang.po $(distdir)/po; \
		cp $(srcdir)/po/$$lang.add $(distdir)/po; \
		$(MKDIR_P) $(distdir)/$$lang; \
		cp -r $(srcdir)/$$lang $(distdir)/; \
	done
