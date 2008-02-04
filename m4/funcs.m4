# Copyright © 2008 Guillem Jover <guillem@debian.org>

# DPKG_FUNC_VA_COPY
# -----------------
# Define HAVE_VA_COPY if we have va_copy, fail if they can't be assigned
AC_DEFUN([DPKG_FUNC_VA_COPY],
[AC_CACHE_CHECK([for va_copy], [dpkg_cv_va_copy],
[AC_TRY_RUN(
[#include <stdarg.h>
main() {
va_list v1, v2;
va_copy (v1, v2);
exit (0);
}],
	[dpkg_cv_va_copy=yes],
	[dpkg_cv_va_copy=no])])
AS_IF([test "x$dpkg_cv_va_copy" = "xyes"],
	[AC_DEFINE([HAVE_VA_COPY], 1,
		  [Define to 1 if the `va_copy' macro exists])],
	[AC_CACHE_CHECK([for va_list assignment by copy],
		       [dpkg_cv_va_list_copy],
[AC_TRY_COMPILE(
[#include <stdarg.h>
],
[va_list v1, v2;
v1 = v2;
],
		       [dpkg_cv_va_list_copy=yes],
		       [dpkg_cv_va_list_copy=no])])])
])# DPKG_FUNC_VA_COPY

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
