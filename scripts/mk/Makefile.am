## Process this file with automake to produce Makefile.in

dist_pkgdata_DATA = \
	architecture.mk \
	buildflags.mk \
	default.mk \
	pkg-info.mk \
	vendor.mk

do_path_subst = $(AM_V_GEN) sed \
	-e "s:dpkg_datadir[[:space:]]*=[[:space:]]*[^[:space:]]*:dpkg_datadir = $(pkgdatadir):"

install-data-hook:
	mv $(DESTDIR)$(pkgdatadir)/default.mk \
	   $(DESTDIR)$(pkgdatadir)/default.mk.tmp
	$(do_path_subst) <$(DESTDIR)$(pkgdatadir)/default.mk.tmp \
	                 >$(DESTDIR)$(pkgdatadir)/default.mk
	rm -f $(DESTDIR)$(pkgdatadir)/default.mk.tmp
