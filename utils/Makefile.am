## Process this file with automake to produce Makefile.in

localedir = $(datadir)/locale
AM_CPPFLAGS = \
	-DADMINDIR=\"$(admindir)\" \
	-DLOCALEDIR=\"$(localedir)\" \
	-DLOGDIR=\"$(logdir)\" \
	-DSYSCONFDIR=\"$(sysconfdir)\" \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_builddir) \
	-I$(top_srcdir)/lib

EXTRA_DIST = \
	README.alternatives \
	$(test_cases)

bin_PROGRAMS =

if WITH_UPDATE_ALTERNATIVES
bin_PROGRAMS += update-alternatives
endif

update_alternatives_SOURCES = \
	update-alternatives.c

update_alternatives_LDADD = \
	../lib/compat/libcompat.a \
	$(LIBINTL) \
	$(UA_LIBS)

sbin_PROGRAMS =

if WITH_START_STOP_DAEMON
sbin_PROGRAMS += start-stop-daemon

start_stop_daemon_SOURCES = \
	start-stop-daemon.c

start_stop_daemon_LDADD = \
	../lib/compat/libcompat.a \
	$(SSD_LIBS)
endif

if WITH_INSTALL_INFO
sbin_PROGRAMS += dpkg-install-info

# Automake has its own install-info rule, gah
dpkg_install_info_SOURCES = install-info.c

dpkg_install_info_LDADD = \
	../lib/compat/libcompat.a
endif

transform = s/dpkg-install-info/install-info/; $(program_transform_name)

install-data-local:
if WITH_UPDATE_ALTERNATIVES
	$(mkdir_p) $(DESTDIR)$(sysconfdir)/alternatives
	$(mkdir_p) $(DESTDIR)$(admindir)/alternatives
	$(INSTALL_DATA) $(srcdir)/README.alternatives $(DESTDIR)$(sysconfdir)/alternatives/README
endif

uninstall-local:
	rm -f $(DESTDIR)$(sysconfdir)/alternatives/README
if WITH_INSTALL_INFO
	rm -f $(DESTDIR)$(sbindir)/install-info
endif

TEST_VERBOSE = 0
TEST_ENV_VARS = DPKG_DATADIR=$(top_srcdir)

test_tmpdir = t.tmp
test_cases = \
	t/100_update_alternatives.t

include $(top_srcdir)/Makecheck.am

clean-local: check-clean
