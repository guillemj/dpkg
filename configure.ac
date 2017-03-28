# Process this file with autoconf to produce a configure script.

m4_pattern_forbid([^_?DPKG_])

AC_PREREQ(2.60)
AC_INIT([dpkg], m4_esyscmd([./get-version]), [debian-dpkg@lists.debian.org])
AC_SUBST([PACKAGE_COPYRIGHT_HOLDER], ['Dpkg Developers'])
AC_CONFIG_SRCDIR([lib/dpkg/dpkg.h])
AC_CONFIG_MACRO_DIR([m4])
AC_CONFIG_AUX_DIR([build-aux])

AC_USE_SYSTEM_EXTENSIONS

AM_INIT_AUTOMAKE([1.11 -Wall foreign nostdinc no-dist-gzip dist-xz])
AM_SILENT_RULES([yes])

# Do not unconditionally use the following macro, as Debian jessie does not
# have a recent enough gettext.
m4_ifdef([
  AM_GNU_GETTEXT_REQUIRE_VERSION
], [
  AM_GNU_GETTEXT_REQUIRE_VERSION([0.19])
])
# We cannot remove the following macro due to backwards compatibility reasons.
# In the future when the gettext version is bumped, we have to set the above
# macro unconditionally to the minimal version, and set the below to 0.19.6,
# the first version introducing the AM_GNU_GETTEXT_REQUIRE_VERSION macro.
AM_GNU_GETTEXT_VERSION([0.19])
AM_GNU_GETTEXT([external])
DPKG_DIST_CHECK([test "$GMSGFMT" = ":" && test "$USE_NLS" = "yes"],
  [gettext required when NLS support enabled])

# Shared libraries are disabled on purpose, currently there is no ABI stability
# guarantee, and it will be broken at will. The infrastructure is in place just
# to be able to test that its future activation will work.
AM_PROG_AR
LT_INIT([disable-shared])
DPKG_BUILD_SHARED_LIBS
DPKG_LINKER_AS_NEEDED
DPKG_LINKER_VERSION_SCRIPT

# Allow compilation without optional programs
DPKG_BUILD_PROG([dselect])
DPKG_BUILD_PROG([start-stop-daemon])
DPKG_BUILD_PROG([update-alternatives])

DPKG_BUILD_RELEASE_DATE
DPKG_BUILD_DEVEL_DOCS

# Allow alternate directories
DPKG_WITH_DIR([devlibdir], [${libdir}],
  [dpkg development library directory [LIBDIR]])
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
DPKG_PROG_PATCH
AC_CHECK_PROGS([DOXYGEN], [doxygen])
AC_CHECK_PROG([HAVE_DOT], [dot], [YES], [NO])
DPKG_PROG_PO4A
DPKG_PROG_PERL
DPKG_PROG_POD2MAN
DPKG_CODE_COVERAGE

# Checks for operating system services and capabilities.
AC_SYS_LARGEFILE

# Checks for libraries.
DPKG_LIB_MD
DPKG_LIB_Z
DPKG_LIB_BZ2
DPKG_LIB_LZMA
DPKG_LIB_SELINUX
AS_IF([test "x$build_dselect" = "xyes"], [
  DPKG_LIB_CURSES
])
AS_IF([test "x$build_start_stop_daemon" = "xyes"], [
  DPKG_LIB_PS
  DPKG_LIB_KVM
])

# Checks for header files.
AC_HEADER_STDC
AC_CHECK_HEADERS([\
  stddef.h \
  error.h \
  err.h \
  locale.h \
  libintl.h \
  kvm.h \
  sys/sysmacros.h \
  sys/param.h \
  sys/sysctl.h \
  sys/syscall.h \
  sys/user.h \
  sys/procfs.h \
  sys/pstat.h \
  linux/fiemap.h \
])
AC_CHECK_HEADERS([sys/proc.h], [], [], [
#ifdef HAVE_SYS_PARAM_H
#include <sys/param.h>
#endif
])

AS_IF([test "x$build_dselect" = "xyes"], [
  AC_LANG_PUSH([C++])
  AC_CHECK_HEADERS([cxxabi.h])
  AC_LANG_POP([C++])
])

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
DPKG_DECL_SYS_ERRLIST

# Checks for library functions.
DPKG_FUNC_VA_COPY
DPKG_FUNC_C99_SNPRINTF
DPKG_CHECK_DECL([offsetof], [stddef.h])
DPKG_CHECK_DECL([makedev], [sys/types.h])
DPKG_CHECK_DECL([WCOREDUMP], [sys/wait.h])
DPKG_CHECK_DECL([TIOCNOTTY], [sys/ioctl.h])
DPKG_CHECK_DECL([O_NOFOLLOW], [fcntl.h])
DPKG_CHECK_DECL([F_ALLOCSP64], [fcntl.h])
DPKG_CHECK_DECL([F_PREALLOCATE], [fcntl.h])
DPKG_CHECK_DECL([P_tmpdir], [stdio.h])
DPKG_CHECK_PROGNAME
DPKG_CHECK_COMPAT_FUNCS([\
  getopt \
  getopt_long \
  obstack_free \
  strnlen \
  strndup \
  strerror \
  strsignal \
  asprintf \
  scandir \
  alphasort \
  unsetenv \
])
AC_CHECK_FUNCS([memcpy lchown],
  [], [AC_MSG_ERROR([missing required function])])
AC_CHECK_FUNCS([\
  strtoimax \
  isascii \
  setsid \
  getdtablesize \
  getprogname \
  getexecname \
  lutimes \
  fallocate \
  posix_fallocate \
  posix_fadvise \
])

AS_IF([test "x$build_dselect" = "xyes"], [
  AC_LANG_PUSH([C++])
  AC_CHECK_FUNCS([__cxa_pure_virtual])
  AC_LANG_POP([C++])
])

DPKG_USE_MMAP
DPKG_USE_DISK_PREALLOCATE

# Checks for the build machinery.
AC_DEFINE([LIBDPKG_VOLATILE_API], [1], [Acknowledge the volatility of the API.])
DPKG_COMPILER_WARNINGS
DPKG_COMPILER_OPTIMIZATIONS
DPKG_LINKER_OPTIMIZATIONS
DPKG_ARCHITECTURE
AC_DEFINE([PACKAGE_RELEASE], [PACKAGE_VERSION " (" ARCHITECTURE ")"],
  [Define the project release information, version and architecture])

AC_CONFIG_TESTDIR([t-func])
AM_MISSING_PROG([AUTOM4TE], [autom4te])

AC_CONFIG_FILES([
  Makefile
  t-func/Makefile
  t-func/atlocal
  dpkg-deb/Makefile
  dpkg-split/Makefile
  dselect/Makefile
  dselect/methods/Makefile
  dselect/po/Makefile.in
  lib/Makefile
  lib/compat/Makefile
  lib/dpkg/Makefile
  lib/dpkg/libdpkg.pc
  lib/dpkg/t/Makefile
  doc/Doxyfile
  man/Makefile
  po/Makefile.in
  scripts/Makefile
  scripts/mk/Makefile
  scripts/po/Makefile.in
  src/Makefile
  utils/Makefile
])
AC_CONFIG_HEADERS([config.h])
AC_OUTPUT

# Print the current configuration
cat <<CONFIG

Configuration:
  Features:
    native language support . . . : $USE_NLS
    unicode support . . . . . . . : $USE_UNICODE
    development documentation . . : $build_devel_docs
    code coverage . . . . . . . . : $enable_coverage
    build shared libraries  . . . : $enable_shared
    mmap loaders  . . . . . . . . : $enable_mmap
    disk pre-allocation . . . . . : $enable_disk_preallocate
    default dpkg-deb compressor . : $with_dpkg_deb_compressor

  Paths:
    devlibdir . . . . . . . . . . : $devlibdir
    pkgconfdir  . . . . . . . . . : $pkgconfdir
    admindir  . . . . . . . . . . : $admindir
    logdir  . . . . . . . . . . . : $logdir
    perl interpreter  . . . . . . : $PERL
    perl libdir . . . . . . . . . : $PERL_LIBDIR

  Programs:
    update-alternatives . . . . . : $build_update_alternatives
    start-stop-daemon . . . . . . : $build_start_stop_daemon
    dselect . . . . . . . . . . . : $build_dselect

  System Libraries:
    libps . . . . . . . . . . . . : ${have_libps:-no}
    libkvm  . . . . . . . . . . . : ${have_libkvm:-no}
    libselinux  . . . . . . . . . : $have_libselinux
    libmd . . . . . . . . . . . . : $have_libmd
    libz  . . . . . . . . . . . . : $have_libz
    liblzma . . . . . . . . . . . : $have_liblzma
    libbz2  . . . . . . . . . . . : $have_libbz2
    libcurses . . . . . . . . . . : ${have_libcurses:-no}
CONFIG
