## Process this file with automake to produce Makefile.in

AM_CPPFLAGS = \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_builddir) \
	# EOL


noinst_LTLIBRARIES = \
	libcompat-test.la \
	libcompat.la \
	# EOL

libcompat_test_la_CPPFLAGS = \
	$(AM_CPPFLAGS) \
	-DTEST_LIBCOMPAT=1 \
	# EOL
libcompat_test_la_SOURCES = \
	compat.h \
	strchrnul.c \
	asprintf.c vasprintf.c \
	# EOL

libcompat_la_SOURCES = \
	empty.c \
	compat.h \
	compat-zlib.h \
	gettext.h \
	# EOL

if !HAVE_GETOPT
libcompat_la_SOURCES += getopt.c getopt.h getopt_int.h
else
if !HAVE_GETOPT_LONG
libcompat_la_SOURCES += getopt.c getopt.h getopt_int.h
endif
endif

if !HAVE_GETOPT_LONG
libcompat_la_SOURCES += getopt1.c
endif

if !HAVE_OBSTACK_FREE
libcompat_la_SOURCES += obstack.c obstack.h
endif

if !HAVE_STRCHRNUL
libcompat_la_SOURCES += strchrnul.c
endif

if !HAVE_ASPRINTF
libcompat_la_SOURCES += asprintf.c vasprintf.c
endif
