# Copyright © 2005 Scott James Remnant <scott@netsplit.com>
# Copyright © 2008, 2009 Guillem Jover <guillem@debian.org>

# DPKG_FUNC_VA_COPY
# -----------------
# Define HAVE_VA_COPY if we have va_copy, fail if they can't be assigned
AC_DEFUN([DPKG_FUNC_VA_COPY],
[AC_CACHE_CHECK([for va_copy], [dpkg_cv_va_copy],
	[AC_RUN_IFELSE([AC_LANG_SOURCE(
[[#include <stdarg.h>
int main()
{
va_list v1, v2;
va_copy (v1, v2);
exit (0);
}
	]])],
	[dpkg_cv_va_copy=yes],
	[dpkg_cv_va_copy=no],
	[dpkg_cv_va_copy=no])])
AS_IF([test "x$dpkg_cv_va_copy" = "xyes"],
	[AC_DEFINE([HAVE_VA_COPY], 1,
	           [Define to 1 if the 'va_copy' macro exists])])
])# DPKG_FUNC_VA_COPY

# DPKG_FUNC_C99_SNPRINTF
# -----------------------
# Define HAVE_C99_SNPRINTF if we have C99 snprintf family semantics
AC_DEFUN([DPKG_FUNC_C99_SNPRINTF],
[AC_CACHE_CHECK([for C99 snprintf functions], [dpkg_cv_c99_snprintf],
	[AC_RUN_IFELSE([AC_LANG_SOURCE([[
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
int test_vsnprintf(const char *fmt, ...)
{
	int n;
	va_list args;

	va_start(args, fmt);
	n = vsnprintf(NULL, 0, fmt, args);
	va_end(args);

	return n;
}
int main()
{
	int n;

	n = snprintf(NULL, 0, "format %s %d", "string", 10);
	if (n != strlen("format string 10"))
		return 1;

	n = test_vsnprintf("format %s %d", "string", 10);
	if (n != strlen("format string 10"))
		return 1;

	return 0;
}
	]])],
	[dpkg_cv_c99_snprintf=yes],
	[dpkg_cv_c99_snprintf=no],
	[dpkg_cv_c99_snprintf=no])])
AS_IF([test "x$dpkg_cv_c99_snprintf" = "xyes"],
	[AC_DEFINE([HAVE_C99_SNPRINTF], 1,
	           [Define to 1 if the 'snprintf' family is C99 conformant])],
	)
AM_CONDITIONAL(HAVE_C99_SNPRINTF, [test "x$dpkg_cv_c99_snprintf" = "xyes"])
])# DPKG_FUNC_C99_SNPRINTF

# DPKG_MMAP
# ---------
# Define USE_MMAP if mmap() is available and it was requested
AC_DEFUN([DPKG_MMAP],
[
  AC_ARG_ENABLE([mmap],
    AS_HELP_STRING([--enable-mmap],
                   [enable usage of unrealiable mmap if available]),
    [],
    [enable_mmap=no])

  AS_IF([test "x$enable_mmap" = "xyes"], [
    AC_CHECK_FUNCS([mmap])
    AC_DEFINE(USE_MMAP, 1, [Use unreliable mmap support])
  ])
])

# DPKG_FUNC_SYNC_SYNC
# --------------------
# Define USE_SYNC_SYNC if sync() is synchronous and it has been enabled
# on configure
AC_DEFUN([DPKG_FUNC_SYNC_SYNC],
[
  AC_REQUIRE([AC_CANONICAL_HOST])

  AC_MSG_CHECKING([whether sync is synchronous])
  AS_CASE([$host_os],
          [linux-*], [dpkg_cv_sync_sync=yes],
          [dpkg_cv_sync_sync=no])
  AC_MSG_RESULT([$dpkg_cv_sync_sync])

  AC_ARG_ENABLE([sync-sync],
    AS_HELP_STRING([--enable-sync-sync],
                   [enable usage of synchronous sync(2) if available]),
    [],
    [enable_sync_sync=no])
  AC_MSG_CHECKING([whether to use synchronous sync])
  AS_IF([test "x$dpkg_cv_sync_sync" = "xyes" &&
         test "x$enable_sync_sync" = "xyes"],
        [AC_DEFINE([USE_SYNC_SYNC], 1,
                   [Define to 1 if sync(2) is synchronous])],
        [enable_sync_sync=no])
  AC_MSG_RESULT([$enable_sync_sync])
])# DPKG_FUNC_SYNC_SYNC

# DPKG_CHECK_COMPAT_FUNCS(LIST)
# -----------------------
# Check each function and define an automake conditional
AC_DEFUN([DPKG_CHECK_COMPAT_FUNCS],
[
  AC_CHECK_FUNCS([$1])
  m4_foreach_w([ac_func], [$1], [
    AM_CONDITIONAL(HAVE_[]AS_TR_CPP(ac_func),
                   [test "x$ac_cv_func_[]AS_TR_SH(ac_func)" = "xyes"])
  ])
]) # DPKG_CHECK_COMPAT_FUNCS
