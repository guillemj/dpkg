# Copyright © 2005 Scott James Remnant <scott@netsplit.com>
# Copyright © 2009 Guillem Jover <guillem@debian.org>

# DPKG_TYPE_PTRDIFF_T
# -------------------
# Check for the ptrdiff_t type, defining to int if not defined
AC_DEFUN([DPKG_TYPE_PTRDIFF_T],
[AC_CHECK_TYPE([ptrdiff_t],,
	AC_DEFINE_UNQUOTED([ptrdiff_t], [int],
			   [Define to 'int' if <malloc.h> does not define.]))dnl
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

# DPKG_CHECK_DECL([DECL], [HEADER])
# -----------------
# Define HAVE_DECL to 1 if declared in HEADER
AC_DEFUN([DPKG_CHECK_DECL],
[
  AC_CHECK_DECL($1,
                [AC_DEFINE([HAVE_]AS_TR_CPP($1), 1,
                           [Define to 1 if ']$1[' is declared in <$2>])],,
                [[#include <$2>]])
])# DPKG_CHECK_DECL
