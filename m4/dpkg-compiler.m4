# Copyright © 2004 Scott James Remnant <scott@netsplit.com>
# Copyright © 2006, 2009-2011, 2013-2016 Guillem Jover <guillem@debian.org>

# DPKG_CHECK_COMPILER_FLAG
# ------------------------
AC_DEFUN([DPKG_CHECK_COMPILER_FLAG], [
  AC_LANG_CASE(
  [C], [
    m4_define([dpkg_compiler], [$CC])
    m4_define([dpkg_varname], [CFLAGS])
    m4_define([dpkg_varname_save], [dpkg_save_CFLAGS])
    m4_define([dpkg_varname_export], [COMPILER_CFLAGS])
    AS_VAR_PUSHDEF([dpkg_varname_cache], [dpkg_cv_cflags_$1])
  ],
  [C++], [
    m4_define([dpkg_compiler], [$CXX])
    m4_define([dpkg_varname], [CXXFLAGS])
    m4_define([dpkg_varname_save], [dpkg_save_CXXFLAGS])
    m4_define([dpkg_varname_export], [COMPILER_CXXFLAGS])
    AS_VAR_PUSHDEF([dpkg_varname_cache], [dpkg_cv_cxxflags_$1])
  ])
  AC_CACHE_CHECK([whether ]dpkg_compiler[ accepts $1], [dpkg_varname_cache], [
    AS_VAR_COPY([dpkg_varname_save], [dpkg_varname])
    AS_VAR_SET([dpkg_varname], ["$1 -Werror"])
    AC_COMPILE_IFELSE([
      AC_LANG_SOURCE([[]])
    ], [
      AS_VAR_SET([dpkg_varname_cache], [yes])
    ], [
      AS_VAR_SET([dpkg_varname_cache], [no])
    ])
    AS_VAR_COPY([dpkg_varname], [dpkg_varname_save])
  ])
  AS_VAR_IF([dpkg_varname_cache], [yes], [
    AS_VAR_APPEND([dpkg_varname_export], [" $1"])
  ])
  AS_VAR_POPDEF([dpkg_varname_cache])
])

# DPKG_CHECK_COMPILER_WARNINGS
# ----------------------------
# Add configure option to disable additional compiler warnings.
AC_DEFUN([DPKG_CHECK_COMPILER_WARNINGS], [
  DPKG_CHECK_COMPILER_FLAG([-Wall])
  DPKG_CHECK_COMPILER_FLAG([-Wextra])
  DPKG_CHECK_COMPILER_FLAG([-Wno-unused-parameter])
  DPKG_CHECK_COMPILER_FLAG([-Wno-missing-field-initializers])
  DPKG_CHECK_COMPILER_FLAG([-Wmissing-declarations])
  DPKG_CHECK_COMPILER_FLAG([-Wmissing-format-attribute])
  DPKG_CHECK_COMPILER_FLAG([-Wformat -Wformat-security])
  DPKG_CHECK_COMPILER_FLAG([-Wsizeof-array-argument])
  DPKG_CHECK_COMPILER_FLAG([-Wpointer-arith])
  DPKG_CHECK_COMPILER_FLAG([-Wlogical-op])
  DPKG_CHECK_COMPILER_FLAG([-Wlogical-not-parentheses])
  DPKG_CHECK_COMPILER_FLAG([-Wswitch-bool])
  DPKG_CHECK_COMPILER_FLAG([-Wvla])
  DPKG_CHECK_COMPILER_FLAG([-Winit-self])
  DPKG_CHECK_COMPILER_FLAG([-Wwrite-strings])
  DPKG_CHECK_COMPILER_FLAG([-Wcast-align])
  DPKG_CHECK_COMPILER_FLAG([-Wshadow])
  DPKG_CHECK_COMPILER_FLAG([-Wduplicated-cond])
  DPKG_CHECK_COMPILER_FLAG([-Wnull-dereference])

  AC_LANG_CASE(
  [C], [
    DPKG_CHECK_COMPILER_FLAG([-Wdeclaration-after-statement])
    DPKG_CHECK_COMPILER_FLAG([-Wnested-externs])
    DPKG_CHECK_COMPILER_FLAG([-Wbad-function-cast])
    DPKG_CHECK_COMPILER_FLAG([-Wstrict-prototypes])
    DPKG_CHECK_COMPILER_FLAG([-Wmissing-prototypes])
    DPKG_CHECK_COMPILER_FLAG([-Wold-style-definition])
    DPKG_CHECK_COMPILER_FLAG([-Wc99-c11-compat])
  ],
  [C++], [
    DPKG_CHECK_COMPILER_FLAG([-Wc++11-compat])
    AS_IF([test "x$dpkg_cv_cxx11" = "xyes"], [
      DPKG_CHECK_COMPILER_FLAG([-Wzero-as-null-pointer-constant])
    ])
  ])
])

# DPKG_COMPILER_WARNINGS
# ----------------------
# Add configure option to disable additional compiler warnings.
AC_DEFUN([DPKG_COMPILER_WARNINGS], [
  AC_ARG_ENABLE([compiler-warnings],
    [AS_HELP_STRING([--disable-compiler-warnings],
      [Disable (detected) additional compiler warnings])],
    [], [enable_compiler_warnings=yes])

  AS_IF([test "x$enable_compiler_warnings" = "xyes"], [
    DPKG_CHECK_COMPILER_WARNINGS
    AC_LANG_PUSH([C++])
    DPKG_CHECK_COMPILER_WARNINGS
    AC_LANG_POP([C++])

    CFLAGS="$COMPILER_CFLAGS $CFLAGS"
    CXXFLAGS="$COMPILER_CXXFLAGS $CXXFLAGS"
  ])
])

# DPKG_COMPILER_OPTIMIZATIONS
# ---------------------------
# Add configure option to disable optimizations.
AC_DEFUN([DPKG_COMPILER_OPTIMIZATIONS], [
  AC_ARG_ENABLE([compiler-optimizations],
    [AS_HELP_STRING([--disable-compiler-optimizations],
      [Disable (detected) compiler optimizations])],
    [], [enable_compiler_optimizations=yes])

  AS_IF([test "x$enable_compiler_optimizations" = "xno"], [
    CFLAGS=$(echo "$CFLAGS" | sed -e "s/ -O[[1-9]]*\b/ -O0/g")
  ])
])

# DPKG_TRY_C99([ACTION-IF-FOUND], [ACTION-IF-NOT-FOUND])
# ------------------------------------------------------
# Try compiling some C99 code to see whether it works
AC_DEFUN([DPKG_TRY_C99], [
  AC_COMPILE_IFELSE([
    AC_LANG_PROGRAM([[
#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>

/* Variadic macro arguments. */
#define variadic_macro(foo, ...) printf(foo, __VA_ARGS__)
    ]], [[
	int rc;

	/* Designated initializers. */
	struct { int a, b; } foo = { .a = 1, .b = 2 };

	/* Compound literals. */
	struct point { int x, y; } p = (struct point){ .x = 0, .y = 1 };
	p = (struct point){ .x = 2, .y = 4 };

	/* Trailing comma in enum. */
	enum { FIRST, SECOND, } quux;

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
    ]])
  ], [$1], [$2])dnl
])# DPKG_TRY_C99

# DPKG_C_C99
# ----------
# Check whether the compiler can do C99
AC_DEFUN([DPKG_C_C99], [
  AC_CACHE_CHECK([whether $CC supports C99 features], [dpkg_cv_c99], [
    DPKG_TRY_C99([dpkg_cv_c99=yes], [dpkg_cv_c99=no])
  ])
  AS_IF([test "x$dpkg_cv_c99" != "xyes"], [
    AC_CACHE_CHECK([for $CC option to accept C99 features], [dpkg_cv_c99_arg], [
      dpkg_cv_c99_arg=none
      dpkg_save_CC="$CC"
      for arg in "-std=gnu99" "-std=c99" "-c99" "-AC99" "-xc99=all" \
                 "-qlanglvl=extc99"; do
        CC="$dpkg_save_CC $arg"
        DPKG_TRY_C99([dpkg_arg_worked=yes], [dpkg_arg_worked=no])
        CC="$dpkg_save_CC"

        AS_IF([test "x$dpkg_arg_worked" = "xyes"], [
          dpkg_cv_c99_arg="$arg"
          break
        ])
      done
    ])
    AS_IF([test "x$dpkg_cv_c99_arg" != "xnone"], [
      CC="$CC $dpkg_cv_c99_arg"
      dpkg_cv_c99=1
    ])
  ])
  AS_IF([test "x$dpkg_cv_c99" = "xyes"], [
    AC_DEFINE([HAVE_C99], 1, [Define to 1 if the compiler supports C99.])
  ], [
    AC_MSG_ERROR([unsupported required C99 extensions])
  ])
])# DPKG_C_C99

# DPKG_TRY_CXX11([ACTION-IF-FOUND], [ACTION-IF-NOT-FOUND])
# --------------
# Try compiling some C++11 code to see whether it works.
AC_DEFUN([DPKG_TRY_CXX11], [
  AC_LANG_PUSH([C++])
  AC_COMPILE_IFELSE([
    AC_LANG_PROGRAM([[
    ]], [[
	// Null pointer keyword.
	void *ptr = nullptr;
    ]])
  ], [$1], [$2])
  AC_LANG_POP([C++])dnl
])# DPKG_TRY_CXX11

# DPKG_CXX_CXX11
# --------------
# Check whether the compiler can do C++11.
AC_DEFUN([DPKG_CXX_CXX11], [
  AC_CACHE_CHECK([whether $CXX supports C++11], [dpkg_cv_cxx11], [
    DPKG_TRY_CXX11([dpkg_cv_cxx11=yes], [dpkg_cv_cxx11=no])
  ])
  AS_IF([test "x$dpkg_cv_cxx11" != "xyes"], [
    AC_CACHE_CHECK([for $CXX option to accept C++11], [dpkg_cv_cxx11_arg], [
      dpkg_cv_cxx11_arg=none
      dpkg_save_CXX="$CXX"
      for arg in "-std=gnu++11" "-std=c++11"; do
        CXX="$dpkg_save_CXX $arg"
        DPKG_TRY_CXX11([dpkg_arg_worked=yes], [dpkg_arg_worked=no])
        CXX="$dpkg_save_CXX"

        AS_IF([test "x$dpkg_arg_worked" = "xyes"], [
          dpkg_cv_cxx11_arg="$arg"; break
        ])
      done
    ])
    AS_IF([test "x$dpkg_cv_cxx11_arg" != "xnone"], [
      CXX="$CXX $dpkg_cv_cxx11_arg"
      dpkg_cv_cxx11=yes
    ])
  ])
  AS_IF([test "x$dpkg_cv_cxx11" = "xyes"], [
    AC_DEFINE([HAVE_CXX11], 1, [Define to 1 if the compiler supports C++11.])
  ])[]dnl
])# DPKG_CXX_CXX11
