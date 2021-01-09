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

CLEANFILES = \
	org.dpkg.pkexec.update-alternatives.policy \
	$(nil)

EXTRA_DIST = \
	README.alternatives \
	update-alternatives.polkit.in \
	$(test_scripts) \
	$(nil)

pkexecdir = $(datadir)/polkit-1/actions
pkexec_DATA =

bin_PROGRAMS =

if BUILD_UPDATE_ALTERNATIVES
pkexec_DATA += org.dpkg.pkexec.update-alternatives.policy
bin_PROGRAMS += update-alternatives
endif

do_polkit_subst = $(SED) \
	-e 's,[@]bindir[@],$(bindir),g' \
	$(nil)

org.dpkg.pkexec.update-alternatives.policy: update-alternatives.polkit.in Makefile
	@test -d `dirname $@` || $(MKDIR_P) `dirname $@`
	$(AM_V_GEN) GETTEXTDATADIR="$(top_srcdir)/po" \
	  $(MSGFMT) --xml --template $< -d $(top_srcdir)/po -o - \
	  | $(do_polkit_subst) >$@

update_alternatives_SOURCES = \
	update-alternatives.c

update_alternatives_CPPFLAGS = \
	-DALT_TMP_EXT=\".dpkg-tmp\" \
	-DADMINDIR_ENVVAR=\"DPKG_ADMINDIR\" \
	-DINSTDIR_ENVVAR=\"DPKG_ROOT\" \
	$(AM_CPPFLAGS)

update_alternatives_LDADD = \
	../lib/compat/libcompat.la \
	$(LIBINTL) \
	$(nil)

sbin_PROGRAMS =

if BUILD_START_STOP_DAEMON
sbin_PROGRAMS += start-stop-daemon

start_stop_daemon_SOURCES = \
	start-stop-daemon.c

start_stop_daemon_LDADD = \
	../lib/compat/libcompat.la \
	$(PS_LIBS) \
	$(KVM_LIBS) \
	$(nil)
endif

install-data-local:
if BUILD_UPDATE_ALTERNATIVES
	$(MKDIR_P) $(DESTDIR)$(sysconfdir)/alternatives
	$(MKDIR_P) $(DESTDIR)$(admindir)/alternatives
	$(INSTALL_DATA) $(srcdir)/README.alternatives $(DESTDIR)$(sysconfdir)/alternatives/README
endif

uninstall-local:
	rm -f $(DESTDIR)$(sysconfdir)/alternatives/README

TEST_ENV_VARS = DPKG_DATADIR=$(top_srcdir)/data

test_tmpdir = t.tmp
test_scripts = \
	t/update_alternatives.t

include $(top_srcdir)/check.am

clean-local: check-clean
