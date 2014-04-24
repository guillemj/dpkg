## Process this file with automake to produce Makefile.in

AM_CPPFLAGS = \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_builddir)


noinst_LIBRARIES = libcompat.a

libcompat_a_SOURCES = \
	empty.c \
	compat.h \
	gettext.h

# FIXME: unconditionally include these for now.
libcompat_a_SOURCES += md5.c md5.h

if !HAVE_GETOPT
libcompat_a_SOURCES += getopt.c getopt.h
endif

if !HAVE_GETOPT_LONG
libcompat_a_SOURCES += getopt1.c
endif

if !HAVE_OBSTACK_FREE
libcompat_a_SOURCES += obstack.c obstack.h
endif

if !HAVE_STRNLEN
libcompat_a_SOURCES += strnlen.c
endif

if !HAVE_STRNDUP
libcompat_a_SOURCES += strndup.c
endif

if !HAVE_STRERROR
libcompat_a_SOURCES += strerror.c
endif

if !HAVE_STRSIGNAL
libcompat_a_SOURCES += strsignal.c
endif

if !HAVE_C99_SNPRINTF
libcompat_a_SOURCES += snprintf.c vsnprintf.c
endif

if !HAVE_ASPRINTF
libcompat_a_SOURCES += asprintf.c vasprintf.c
endif

if !HAVE_ALPHASORT
libcompat_a_SOURCES += alphasort.c
endif

if !HAVE_SCANDIR
libcompat_a_SOURCES += scandir.c
endif

if !HAVE_UNSETENV
libcompat_a_SOURCES += unsetenv.c
endif
