# Copyright © 2004 Scott James Remnant <scott@netsplit.com>
# Copyright © 2006, 2009-2011, 2013 Guillem Jover <guillem@debian.org>

# DPKG_WARNING_CC
# ---------------
AC_DEFUN([DPKG_WARNING_CC], [
  AS_VAR_PUSHDEF([cache_var_name], [dpkg_cv_cflag_$1])
  AC_CACHE_CHECK([whether $CC accepts $1], [cache_var_name], [
    dpkg_save_CFLAGS="$CFLAGS"
    CFLAGS="$1"
    AC_LANG_PUSH([C])
    AC_COMPILE_IFELSE([
      AC_LANG_SOURCE([[]])
    ], [
      AS_VAR_SET([cache_var_name], [yes])
    ],[
      AS_VAR_SET([cache_var_name], [no])
    ])
    AC_LANG_POP([C])
    CFLAGS="$dpkg_save_CFLAGS"
  ])
  AS_VAR_IF([cache_var_name], [yes], [CWARNFLAGS="$CWARNFLAGS $1"])
  AS_VAR_POPDEF([cache_var_name])
])

# DPKG_WARNING_CXX
# ----------------
AC_DEFUN([DPKG_WARNING_CXX], [
  AS_VAR_PUSHDEF([cache_var_name], [dpkg_cv_cxxflag_$1])
  AC_CACHE_CHECK([whether $CXX accepts $1], [cache_var_name], [
    dpkg_save_CXXFLAGS="$CXXFLAGS"
    CXXFLAGS="$1"
    AC_LANG_PUSH([C++])
    AC_COMPILE_IFELSE([
      AC_LANG_SOURCE([[]])
    ], [
      AS_VAR_SET([cache_var_name], [yes])
    ], [
      AS_VAR_SET([cache_var_name], [no])
    ])
    AC_LANG_POP([C++])
    CXXFLAGS="$dpkg_save_CXXFLAGS"
  ])
  AS_VAR_IF([cache_var_name], [yes], [CXXWARNFLAGS="$CXXWARNFLAGS $1"])
  AS_VAR_POPDEF([cache_var_name])
])

# DPKG_WARNING_ALL
# ----------------
AC_DEFUN([DPKG_WARNING_ALL], [
  DPKG_WARNING_CC([$1])
  DPKG_WARNING_CXX([$1])
])

# DPKG_COMPILER_WARNINGS
# ---------------------
# Add configure option to disable additional compiler warnings.
AC_DEFUN([DPKG_COMPILER_WARNINGS],
[AC_ARG_ENABLE(compiler-warnings,
	AS_HELP_STRING([--disable-compiler-warnings],
	               [Disable additional compiler warnings]),
	[],
	[enable_compiler_warnings=yes])

if test "x$enable_compiler_warnings" = "xyes"; then
  DPKG_WARNING_ALL([-Wall])
  DPKG_WARNING_ALL([-Wextra])
  DPKG_WARNING_ALL([-Wno-unused-parameter])
  DPKG_WARNING_ALL([-Wno-missing-field-initializers])
  DPKG_WARNING_ALL([-Wmissing-declarations])
  DPKG_WARNING_ALL([-Wmissing-format-attribute])
  DPKG_WARNING_ALL([-Wformat-security])
  DPKG_WARNING_ALL([-Wpointer-arith])
  DPKG_WARNING_ALL([-Wlogical-op])
  DPKG_WARNING_ALL([-Wvla])
  DPKG_WARNING_ALL([-Winit-self])
  DPKG_WARNING_ALL([-Wwrite-strings])
  DPKG_WARNING_ALL([-Wcast-align])
  DPKG_WARNING_ALL([-Wshadow])

  DPKG_WARNING_CC([-Wdeclaration-after-statement])
  DPKG_WARNING_CC([-Wnested-externs])
  DPKG_WARNING_CC([-Wbad-function-cast])
  DPKG_WARNING_CC([-Wstrict-prototypes])
  DPKG_WARNING_CC([-Wmissing-prototypes])
  DPKG_WARNING_CC([-Wold-style-definition])

  DPKG_WARNING_CXX([-Wc++11-compat])

  CFLAGS="$CWARNFLAGS $CFLAGS"
  CXXFLAGS="$CXXWARNFLAGS $CXXFLAGS"
fi
])

# DPKG_COMPILER_OPTIMISATIONS
# --------------------------
# Add configure option to disable optimisations.
AC_DEFUN([DPKG_COMPILER_OPTIMISATIONS],
[AC_ARG_ENABLE(compiler-optimisations,
	AS_HELP_STRING([--disable-compiler-optimisations],
		       [Disable compiler optimisations]),
	[],
	[enable_compiler_optimisations=yes])

  AS_IF([test "x$enable_compiler_optimisations" = "xno"], [
    CFLAGS=$(echo "$CFLAGS" | sed -e "s/ -O[[1-9]]*\b/ -O0/g")
  ])
])

# DPKG_TRY_C99([ACTION-IF-FOUND], [ACTION-IF-NOT-FOUND])
# ------------------------------------------------------
# Try compiling some C99 code to see whether it works
AC_DEFUN([DPKG_TRY_C99],
[AC_COMPILE_IFELSE([AC_LANG_PROGRAM([[
#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>

/* Variadic macro arguments. */
#define variadic_macro(foo, ...) printf(foo, __VA_ARGS__)
]],
[[
	int rc;

	/* Compound initializers. */
	struct { int a, b; } foo = { .a = 1, .b = 2 };

	/* Trailing comma in enum. */
	enum { first, second, } quux;

	/* Boolean type. */
	bool bar = false;

	/* Specific size type. */
	uint32_t baz = 0;
	size_t size = SIZE_MAX;
	intmax_t imax = INTMAX_MAX;

	/* Format modifiers. */
	rc = printf("%jd", imax);
	if (rc == 3)
		return 1;
	rc = printf("%zu", size);
	if (rc == 3)
		return 1;

	/* Magic __func__ variable. */
	printf("%s", __func__);
]])], [$1], [$2])dnl
])# DPKG_TRY_C99

# DPKG_C_C99
# ----------
# Check whether the compiler can do C99
AC_DEFUN([DPKG_C_C99],
[AC_CACHE_CHECK([whether $CC supports C99 features], [dpkg_cv_c99],
	[DPKG_TRY_C99([dpkg_cv_c99=yes], [dpkg_cv_c99=no])])
AS_IF([test "x$dpkg_cv_c99" = "xyes"],
	[AC_DEFINE([HAVE_C99], 1, [Define to 1 if the compiler supports C99.])],
	[AC_CACHE_CHECK([for $CC option to accept C99 features],
		[dpkg_cv_c99_arg],
		[dpkg_cv_c99_arg=none
		 dpkg_save_CC="$CC"
		 for arg in "-std=gnu99" "-std=c99" "-c99" "-AC99" \
		            "-xc99=all" "-qlanglvl=extc99"; do
		    CC="$dpkg_save_CC $arg"
		    DPKG_TRY_C99([dpkg_arg_worked=yes], [dpkg_arg_worked=no])
		    CC="$dpkg_save_CC"

		    AS_IF([test "x$dpkg_arg_worked" = "xyes"],
			  [dpkg_cv_c99_arg="$arg"; break])
		 done])
	 AS_IF([test "x$dpkg_cv_c99_arg" != "xnone"],
	       [CC="$CC $dpkg_cv_c99_arg"
		AC_DEFINE([HAVE_C99], 1)],
	       [AC_MSG_ERROR([unsupported required C99 extensions])])])[]dnl
])# DPKG_C_C99
