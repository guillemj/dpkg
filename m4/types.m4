# DPKG_TYPE_PTRDIFF_T
# -------------------
# Check for the ptrdiff_t type, defining to int if not defined
AC_DEFUN([DPKG_TYPE_PTRDIFF_T],
[AC_CHECK_TYPE([ptrdiff_t],,
	AC_DEFINE_UNQUOTED([ptrdiff_t], [int],
			   [Define to `int' if <malloc.h> does not define.]))dnl
])# DPKG_TYPE_PTRDIFF_T

# DPKG_DECL_SYS_SIGLIST
# ---------------------
# Check for the sys_siglist variable in either signal.h or unistd.h
AC_DEFUN([DPKG_DECL_SYS_SIGLIST],
[AC_CHECK_HEADERS([unistd.h])
AC_CHECK_DECLS([sys_siglist],,,
[#include <signal.h>
/* NetBSD declares sys_siglist in unistd.h.  */
#if HAVE_UNISTD_H
#  include <unistd.h>
#endif
])dnl
])# DPKG_DECL_SYS_SIGLIST

# DPKG_CHECK_DEFINE([DEFINE], [HEADER])
# -------------------------------------
# Defines HAVE_DEFINE to 1 if declared in HEADER, 0 otherwise
AC_DEFUN([DPKG_CHECK_DEFINE],
[AC_CACHE_CHECK([whether $1 is defined in $2], [dpkg_cv_define_$1],
[AC_TRY_COMPILE(
[#include <$2>
],
[int i = $1;
],
	[dpkg_cv_define_$1=yes],
	[dpkg_cv_define_$1=no])])
AS_IF([test "x$dpkg_cv_define" = "xyes"],
	[AC_DEFINE([HAVE_]$1, 1, [Define to 1 if you have the macro `]$1[' in
				  `]$2[', and to 0 if you don't.])],
	[AC_DEFINE([HAVE_]$1, 0)])[]dnl
])# DPKG_CHECK_DEFINE
