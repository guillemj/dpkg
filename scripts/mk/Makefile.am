## Process this file with automake to produce Makefile.in

dist_pkgdata_DATA = \
	architecture.mk \
	buildflags.mk \
	default.mk \
	vendor.mk

do_path_subst = $(AM_V_GEN) \
                sed -e "s:dpkg_datadir[[:space:]]*=[[:space:]]*[^[:space:]]*:dpkg_datadir = $(pkgdatadir):"

install-data-hook:
	cp -p $(DESTDIR)$(pkgdatadir)/default.mk $(DESTDIR)$(pkgdatadir)/default.mk.tmp
	$(do_path_subst) <$(DESTDIR)$(pkgdatadir)/default.mk.tmp \
			 >$(DESTDIR)$(pkgdatadir)/default.mk
	rm $(DESTDIR)$(pkgdatadir)/default.mk.tmp
