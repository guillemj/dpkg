## Process this file with automake to produce Makefile.in

dist_man_MANS = \
	822-date.1 \
	cleanup-info.8 \
	deb-control.5 \
	deb-old.5 \
	deb.5 \
	dpkg-architecture.1 \
	dpkg-checkbuilddeps.1 \
	dpkg-deb.1 \
	dpkg-divert.8 \
	dpkg-name.1 \
	dpkg-query.1 \
	dpkg-scanpackages.1 \
	dpkg-scansources.1 \
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

dpkg_source_aliases = \
	dpkg-buildpackage.1 \
	dpkg-distaddfile.1 \
	dpkg-genchanges.1 \
	dpkg-gencontrol.1 \
	dpkg-parsechangelog.1 \
	dpkg-shlibdeps.1

man_MANS = $(dpkg_source_aliases)
CLEANFILES = $(dpkg_source_aliases)


$(dpkg_source_aliases):
	echo ".so man1/dpkg-source.1" > $@
	chmod 644 $@
