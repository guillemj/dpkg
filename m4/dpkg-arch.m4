# Copyright © 2005 Scott James Remnant <scott@netsplit.com>
# Copyright © 2006-2009 Guillem Jover <guillem@debian.org>

# _DPKG_ARCHITECTURE([DEB_VAR], [sh_var])
# ---------------------------------------
# Use dpkg-architecture from the source tree to set sh_var using DEB_VAR for
# the target architecture, to avoid duplicating its logic.
AC_DEFUN([_DPKG_ARCHITECTURE], [
  AC_REQUIRE([DPKG_PROG_PERL])dnl
  AC_REQUIRE([AC_CANONICAL_HOST])dnl
  $2=$(PERL=$PERL $srcdir/run-script scripts/dpkg-architecture.pl -t$host -q$1 2>/dev/null)
])# _DPKG_ARCHITECTURE

# DPKG_CPU_TYPE
# -------------
# Parse the host cpu name and check it against the cputable to determine
# the Debian name for it.  Sets ARCHITECTURE_CPU.
AC_DEFUN([DPKG_CPU_TYPE], [
  AC_MSG_CHECKING([dpkg cpu type])
  _DPKG_ARCHITECTURE([DEB_HOST_ARCH_CPU], [cpu_type])
  AS_IF([test "x$cpu_type" = "x"], [
    cpu_type=$host_cpu
    AC_MSG_RESULT([$cpu_type])
    AC_MSG_WARN([$host_cpu not found in cputable])
  ], [
    AC_MSG_RESULT([$cpu_type])
  ])
  AC_DEFINE_UNQUOTED([ARCHITECTURE_CPU], ["${cpu_type}"],
    [Set this to the canonical dpkg CPU name.])
])# DPKG_CPU_TYPE

# DPKG_OS_TYPE
# ------------
# Parse the host operating system name and check it against a list of
# special cases to determine what type it is.  Sets ARCHITECTURE_OS.
AC_DEFUN([DPKG_OS_TYPE], [
  AC_MSG_CHECKING([dpkg operating system type])
  _DPKG_ARCHITECTURE([DEB_HOST_ARCH_OS], [os_type])
  AS_IF([test "x$os_type" = "x"], [
    os_type=$host_os
    AC_MSG_RESULT([$os_type])
    AC_MSG_WARN([$host_os not found in ostable])
  ], [
    AC_MSG_RESULT([$os_type])
  ])
  AC_DEFINE_UNQUOTED([ARCHITECTURE_OS], ["${os_type}"],
    [Set this to the canonical dpkg system name.])
])# DPKG_OS_TYPE

# DPKG_ARCHITECTURE
# ------------------------
# Determine the Debian name for the host operating system,
# sets ARCHITECTURE.
AC_DEFUN([DPKG_ARCHITECTURE], [
  DPKG_CPU_TYPE
  DPKG_OS_TYPE
  AC_MSG_CHECKING([dpkg architecture name])
  _DPKG_ARCHITECTURE([DEB_HOST_ARCH], [dpkg_arch])
  AS_IF([test "x$dpkg_arch" = "x"], [
    AC_MSG_ERROR([cannot determine host dpkg architecture])
  ], [
    AC_MSG_RESULT([$dpkg_arch])
  ])
  AC_DEFINE_UNQUOTED([ARCHITECTURE], ["${dpkg_arch}"],
    [Set this to the canonical dpkg architecture name.])
])# DPKG_ARCHITECTURE
