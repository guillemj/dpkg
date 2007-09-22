## Process this file with automake to produce Makefile.in

all-local: man.stamp

# FIXME: Use a stamp file until po4a supports them internally.
man.stamp:
	po4a --no-backups --variable srcdir=$(srcdir) \
		$(srcdir)/po/po4a.cfg
	touch $@

clean-local:
	po4a --rm-backups --rm-translations --variable srcdir=$(srcdir) \
		$(srcdir)/po/po4a.cfg
	rm -f man.stamp

# Extract the list of languages from the po4a config file.
LINGUAS = $(shell sed -ne 's/^.*\[po4a_langs\] \(.*\)$$/\1/p' $(srcdir)/po/po4a.cfg)

install-data-local:
	for lang in $(LINGUAS); do \
		if [ -d $(srcdir)/$$lang ]; then \
			files=$$(echo $(srcdir)/$$lang/*.[1-9]); \
			$(MAKE) install-man \
				mandir="$(mandir)/$$lang" \
				man_MANS="" \
				dist_man_MANS="$$files"; \
		fi \
	done

uninstall-local:
	for lang in $(LINGUAS); do \
		if [ -d $(srcdir)/$$lang ]; then \
			files=$$(echo $(srcdir)/$$lang/*.[1-9]); \
			$(MAKE) uninstall-man \
				mandir="$(mandir)/$$lang" \
				man_MANS="" \
				dist_man_MANS="$$files"; \
		fi \
	done

dist-hook: man.stamp
	cp $(srcdir)/man.stamp $(distdir)/
	for lang in $(LINGUAS); do \
		cp $(srcdir)/po/$$lang.po $(distdir)/po; \
		cp $(srcdir)/po/$$lang.add $(distdir)/po; \
		$(mkdir_p) $(distdir)/$$lang; \
		cp -r $(srcdir)/$$lang $(distdir)/; \
	done

dist_man_MANS = \
	822-date.1 \
	cleanup-info.8 \
	deb-control.5 \
	deb-shlibs.5 \
	deb-substvars.5 \
	deb-symbols.5 \
	deb-old.5 \
	deb-override.5 \
	deb.5 \
	dpkg-architecture.1 \
	dpkg-buildpackage.1 \
	dpkg-checkbuilddeps.1 \
	dpkg-deb.1 \
	dpkg-distaddfile.1 \
	dpkg-divert.8 \
	dpkg-genchanges.1 \
	dpkg-gencontrol.1 \
	dpkg-gensymbols.1 \
	dpkg-name.1 \
	dpkg-parsechangelog.1 \
	dpkg-query.1 \
	dpkg-scanpackages.1 \
	dpkg-scansources.1 \
	dpkg-shlibdeps.1 \
	dpkg-source.1 \
	dpkg-split.1 \
	dpkg-statoverride.8 \
	dpkg.1 \
	dpkg.cfg.5 \
	dselect.1 \
	dselect.cfg.5 \
	install-info.8 \
	start-stop-daemon.8 \
	update-alternatives.8

EXTRA_DIST = \
	po/po4a.cfg \
	po/dpkg-man.pot

