## Process this file with automake to produce Makefile.in

AM_CPPFLAGS = \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_builddir)


noinst_LTLIBRARIES = libcompat-test.la libcompat.la

libcompat_test_la_CPPFLAGS = $(AM_CPPFLAGS) -DTEST_LIBCOMPAT=1
libcompat_test_la_SOURCES = \
	compat.h \
	strnlen.c \
	strndup.c \
	strerror.c \
	strsignal.c \
	snprintf.c vsnprintf.c \
	asprintf.c vasprintf.c \
	alphasort.c \
	scandir.c \
	unsetenv.c

libcompat_la_SOURCES = \
	empty.c \
	compat.h \
	gettext.h

# FIXME: unconditionally include these for now.
libcompat_la_SOURCES += md5.c md5.h

if !HAVE_GETOPT
libcompat_la_SOURCES += getopt.c getopt.h
endif

if !HAVE_GETOPT_LONG
libcompat_la_SOURCES += getopt1.c
endif

if !HAVE_OBSTACK_FREE
libcompat_la_SOURCES += obstack.c obstack.h
endif

if !HAVE_STRNLEN
libcompat_la_SOURCES += strnlen.c
endif

if !HAVE_STRNDUP
libcompat_la_SOURCES += strndup.c
endif

if !HAVE_STRERROR
libcompat_la_SOURCES += strerror.c
endif

if !HAVE_STRSIGNAL
libcompat_la_SOURCES += strsignal.c
endif

if !HAVE_C99_SNPRINTF
libcompat_la_SOURCES += snprintf.c vsnprintf.c
endif

if !HAVE_ASPRINTF
libcompat_la_SOURCES += asprintf.c vasprintf.c
endif

if !HAVE_ALPHASORT
libcompat_la_SOURCES += alphasort.c
endif

if !HAVE_SCANDIR
libcompat_la_SOURCES += scandir.c
endif

if !HAVE_UNSETENV
libcompat_la_SOURCES += unsetenv.c
endif
