# Copyright © 2004 Scott James Remnant <scott@netsplit.com>.
# Copyright © 2010, 2014 Guillem Jover <guillem@debian.org>

# DPKG_LINKER_OPTIMISATIONS
# --------------------------
# Add configure option to disable linker optimisations.
AC_DEFUN([DPKG_LINKER_OPTIMISATIONS],
[AC_ARG_ENABLE(linker-optimisations,
	AS_HELP_STRING([--disable-linker-optimisations],
		       [Disable linker optimisations]),
    [],
    [enable_linker_optimisations=yes])

  AS_IF([test "x$enable_linker_optimisations" = "xno"], [
    LDFLAGS=$(echo "$LDFLAGS" | sed -e "s/ -Wl,-O[[0-9]]*\b//g")
  ], [
    LDFLAGS="$LDFLAGS -Wl,-O1"
  ])
])

# DPKG_LINKER_VERSION_SCRIPT
# --------------------------
AC_DEFUN([DPKG_LINKER_VERSION_SCRIPT],
[
  AC_CACHE_CHECK([for --version-script linker flag],
    [dpkg_cv_version_script],
    [echo "{ global: symbol; local: *; };" >conftest.map
    save_LDFLAGS=$LDFLAGS
    LDFLAGS="$LDFLAGS -Wl,--version-script=conftest.map"
    AC_LINK_IFELSE([AC_LANG_PROGRAM([], [])],
                   [dpkg_cv_version_script=yes],
                   [dpkg_cv_version_script=no])
    LDFLAGS="$save_LDFLAGS"
    rm -f conftest.map
  ])
  AM_CONDITIONAL([HAVE_LINKER_VERSION_SCRIPT],
                 [test "x$dpkg_cv_version_script" = "xyes"])
])
