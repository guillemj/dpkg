## Process this file with automake to produce Makefile.in

localedir = $(datadir)/locale
INCLUDES = \
	-DLOCALEDIR=\"$(localedir)\" \
	-idirafter $(top_srcdir)/libcompat \
	-I$(top_srcdir)/lib

sbin_PROGRAMS =

if WITH_START_STOP_DAEMON
  sbin_PROGRAMS += start-stop-daemon

  start_stop_daemon_SOURCES = \
	start-stop-daemon.c

  start_stop_daemon_LDADD = ../libcompat/libcompat.a $(SSD_LIBS)
endif

sbin_PROGRAMS += dpkg-install-info

# Automake has its own install-info rule, gah
dpkg_install_info_SOURCES = install-info.c

dpkg_install_info_LDADD = ../libcompat/libcompat.a

transform = s/dpkg-install-info/install-info/; $(program_transform_name)

