## Process this file with automake to produce Makefile.in

localedir = $(datadir)/locale
AM_CPPFLAGS = \
	-DLOCALEDIR=\"$(localedir)\" \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_builddir) \
	-I$(top_srcdir)/lib

sbin_PROGRAMS =

if WITH_START_STOP_DAEMON
  sbin_PROGRAMS += start-stop-daemon

  start_stop_daemon_SOURCES = \
	start-stop-daemon.c

  start_stop_daemon_LDADD = \
	../lib/compat/libcompat.a \
	$(SSD_LIBS)
endif

sbin_PROGRAMS += dpkg-install-info

# Automake has its own install-info rule, gah
dpkg_install_info_SOURCES = install-info.c

dpkg_install_info_LDADD = \
	../lib/compat/libcompat.a

transform = s/dpkg-install-info/install-info/; $(program_transform_name)

