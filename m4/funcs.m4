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
