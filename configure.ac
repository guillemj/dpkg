# Process this file with autoconf to produce a configure script.

AC_PREREQ(2.59)
AC_INIT([dpkg], [1.14.30], [debian-dpkg@lists.debian.org])
AC_CONFIG_SRCDIR([lib/dpkg.h])
AC_CONFIG_MACRO_DIR([m4])
AC_CONFIG_AUX_DIR([config])

AC_CANONICAL_SYSTEM
AC_GNU_SOURCE
DPKG_ARCHITECTURE

AM_INIT_AUTOMAKE([1.8 gnu])

AM_GNU_GETTEXT_VERSION([0.16.1])
AM_GNU_GETTEXT([external])

# Allow compilation without dselect
AC_ARG_WITH(dselect,
	AS_HELP_STRING([--without-dselect],
		       [don't build dselect package-management frontend]),
	[build_dselect=$with_dselect],
	[build_dselect=yes])
AM_CONDITIONAL(WITH_DSELECT, [test "x$build_dselect" = "xyes"])

# Allow compilation without start-stop-daemon
AC_ARG_WITH(start-stop-daemon,
	AS_HELP_STRING([--without-start-stop-daemon],
		       [don't build or use start-stop-daemon]),
	[build_start_stop_daemon=$with_start_stop_daemon],
	[build_start_stop_daemon=yes])
AM_CONDITIONAL(WITH_START_STOP_DAEMON,
	[test "x$build_start_stop_daemon" = "xyes"])
if test "x$build_start_stop_daemon" = "xyes"; then
   AC_DEFINE(WITH_START_STOP_DAEMON, 1,
	[Define to 1 if start-stop-daemon is compiled.])
else
   AC_DEFINE(WITH_START_STOP_DAEMON, 0)
fi

# Allow alternate admin directory
admindir="${localstatedir}/${PACKAGE_NAME}"
AC_ARG_WITH(admindir,
	AS_HELP_STRING([--with-admindir=DIR],
		       [dpkg database directory [[LOCALSTATEDIR/dpkg]]]),
[case "$with_admindir" in
      "") AC_MSG_ERROR([invalid admindir specified]) ;;
      *) admindir="$with_admindir" ;;
esac])
AC_SUBST(admindir)


# Checks for programs.
AC_PROG_CC
AC_PROG_CXX
AC_PROG_LEX
AC_PROG_RANLIB
DPKG_PROG_PERL

# Checks for operating system services and capabilities.
AC_SYS_LARGEFILE

# Checks for libraries.
DPKG_LIB_ZLIB
DPKG_LIB_BZ2
DPKG_LIB_SELINUX
if test "x$build_dselect" = "xyes"; then
   DPKG_LIB_CURSES
fi
if test "x$build_start_stop_daemon" = "xyes"; then
   DPKG_LIB_SSD
fi

# Checks for header files.
AC_HEADER_STDC
AC_CHECK_HEADERS([stddef.h error.h locale.h libintl.h sys/cdefs.h kvm.h])
DPKG_CHECK_DEFINE(TIOCNOTTY, [sys/ioctl.h])

# Checks for typedefs, structures, and compiler characteristics.
AC_C_BIGENDIAN
AC_C_CONST
AC_C_INLINE
AC_C_VOLATILE
DPKG_C_C99
AC_TYPE_MODE_T
AC_TYPE_PID_T
AC_TYPE_SIZE_T
DPKG_TYPE_PTRDIFF_T
AC_CHECK_SIZEOF([unsigned int])
AC_CHECK_SIZEOF([unsigned long])
DPKG_DECL_SYS_SIGLIST
DPKG_C_ATTRIBUTE

# Checks for library functions.
DPKG_FUNC_VA_COPY
DPKG_CHECK_COMPAT_FUNCS([getopt getopt_long strnlen obstack_free])
AC_CHECK_FUNCS([vsnprintf snprintf strtoul strerror strsignal alphasort \
                isascii bcopy memcpy scandir unsetenv lchown setsid \
                getdtablesize])

SJR_COMPILER_WARNINGS
SJR_COMPILER_OPTIMISATIONS
SJR_LINKER_OPTIMISATIONS

AC_CONFIG_FILES([ Makefile
		  dpkg-deb/Makefile
		  dpkg-split/Makefile
		  dselect/Makefile
		  dselect/methods/Makefile
		  dselect/po/Makefile.in
		  libcompat/Makefile
		  lib/Makefile
		  man/Makefile
		  origins/Makefile
		  po/Makefile.in
		  scripts/Makefile
		  scripts/po/Makefile.in
		  src/Makefile
		  utils/Makefile ])
AC_CONFIG_HEADERS([config.h])
AC_OUTPUT
