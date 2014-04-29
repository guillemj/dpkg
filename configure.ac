# Process this file with autoconf to produce a configure script.

m4_pattern_forbid([^_?DPKG_])

AC_PREREQ(2.60)
AC_INIT([dpkg], m4_esyscmd([./get-version]), [debian-dpkg@lists.debian.org])
AC_CONFIG_SRCDIR([lib/dpkg/dpkg.h])
AC_CONFIG_MACRO_DIR([m4])
AC_CONFIG_AUX_DIR([build-aux])

AC_USE_SYSTEM_EXTENSIONS

AM_INIT_AUTOMAKE([1.11 foreign nostdinc no-dist-gzip dist-xz])
AM_SILENT_RULES([yes])

AM_GNU_GETTEXT_VERSION([0.18.2])
AM_GNU_GETTEXT([external])
DPKG_DIST_CHECK([test "$GMSGFMT" = ":" && test "$USE_NLS" = "yes"],
                [gettext required when NLS support enabled])

# Allow compilation without optional programs
DPKG_BUILD_PROG([dselect])
DPKG_BUILD_PROG([start-stop-daemon])
DPKG_BUILD_PROG([update-alternatives])

# Allow alternate directories
DPKG_WITH_DIR([pkgconfdir], [${sysconfdir}/${PACKAGE_NAME}],
              [dpkg configuration directory [SYSCONFDIR/dpkg]])
DPKG_WITH_DIR([admindir], [${localstatedir}/lib/${PACKAGE_NAME}],
              [dpkg database directory [LOCALSTATEDIR/lib/dpkg]])
DPKG_WITH_DIR([logdir], [${localstatedir}/log],
              [system logging directory [LOCALSTATEDIR/log]])

# Set default dpkg-deb values
DPKG_DEB_COMPRESSOR([xz])
DPKG_DEB_PROG_TAR

# Checks for programs.
AC_PROG_CC
DPKG_C_C99
AC_PROG_CXX
DPKG_CXX_CXX11
AC_PROG_LEX
DPKG_DIST_CHECK([test "$LEX" = ":"], [lex program required])
AC_PROG_RANLIB
AC_CHECK_PROGS([DOXYGEN], [doxygen])
AC_CHECK_PROG([HAVE_DOT], [dot], [YES], [NO])
DPKG_PROG_PO4A
DPKG_PROG_PERL
DPKG_PROG_POD2MAN
DPKG_CODE_COVERAGE

# Checks for operating system services and capabilities.
AC_SYS_LARGEFILE

# Checks for libraries.
DPKG_LIB_ZLIB
DPKG_LIB_BZ2
DPKG_LIB_LZMA
DPKG_LIB_SELINUX
if test "x$build_dselect" = "xyes"; then
   DPKG_LIB_CURSES
fi
if test "x$build_start_stop_daemon" = "xyes"; then
   DPKG_LIB_SSD
fi

# Checks for header files.
AC_HEADER_STDC
AC_CHECK_HEADERS([stddef.h error.h err.h locale.h libintl.h kvm.h \
                  sys/param.h sys/sysctl.h sys/syscall.h sys/user.h \
                  sys/proc.h sys/pstat.h linux/fiemap.h])

# Checks for typedefs, structures, and compiler characteristics.
AC_C_BIGENDIAN
AC_C_CONST
AC_C_INLINE
AC_C_VOLATILE
AC_TYPE_MODE_T
AC_TYPE_PID_T
AC_TYPE_SIZE_T
DPKG_TYPES_U_INT_T
DPKG_TYPE_PTRDIFF_T
AC_CHECK_SIZEOF([unsigned int])
AC_CHECK_SIZEOF([unsigned long])
DPKG_DECL_SYS_SIGLIST

# Checks for library functions.
DPKG_FUNC_VA_COPY
DPKG_FUNC_C99_SNPRINTF
DPKG_CHECK_DECL([offsetof], [stddef.h])
DPKG_CHECK_DECL([makedev], [sys/types.h])
DPKG_CHECK_DECL([WCOREDUMP], [sys/wait.h])
DPKG_CHECK_DECL([TIOCNOTTY], [sys/ioctl.h])
DPKG_CHECK_DECL([O_NOFOLLOW], [fcntl.h])
DPKG_CHECK_DECL([P_tmpdir], [stdio.h])
DPKG_CHECK_PROGNAME
DPKG_CHECK_COMPAT_FUNCS([getopt getopt_long obstack_free \
                         strnlen strndup strerror strsignal asprintf \
                         scandir alphasort unsetenv])
AC_CHECK_DECLS([strnlen], [[#include <string.h>]])
AC_CHECK_FUNCS([memcpy lchown],
               [], [AC_MSG_ERROR([missing required function])])
AC_CHECK_FUNCS([strtoimax isascii setsid getdtablesize \
                getprogname getexecname lutimes posix_fadvise])

DPKG_MMAP

# Checks for the build machinery.
AC_DEFINE(LIBDPKG_VOLATILE_API, 1, [Acknowledge the volatility of the API.])
DPKG_COMPILER_WARNINGS
DPKG_COMPILER_OPTIMISATIONS
DPKG_LINKER_OPTIMISATIONS
DPKG_ARCHITECTURE

AC_CONFIG_FILES([ Makefile
		  dpkg-deb/Makefile
		  dpkg-split/Makefile
		  dselect/Makefile
		  dselect/methods/Makefile
		  dselect/po/Makefile.in
		  lib/Makefile
		  lib/compat/Makefile
		  lib/dpkg/Makefile
		  lib/dpkg/libdpkg.pc
		  lib/dpkg/test/Makefile
		  doc/Doxyfile
		  man/Makefile
		  po/Makefile.in
		  scripts/Makefile
		  scripts/mk/Makefile
		  scripts/po/Makefile.in
		  src/Makefile
		  utils/Makefile ])
AC_CONFIG_HEADERS([config.h])
AC_OUTPUT
