# DPKG_LIB_ZLIB
# -------------
# Check for zlib library.
AC_DEFUN([DPKG_LIB_ZLIB],
[AC_ARG_VAR([ZLIB_LIBS], [linker flags for zlib library])dnl
AC_ARG_WITH(zlib,
	AS_HELP_STRING([--with-zlib],
		       [use zlib library for compression and decompression]))
if test "x$with_zlib" != "xno"; then
	AC_CHECK_LIB([z], [gzdopen],
		[AC_DEFINE(WITH_ZLIB, 1,
			[Define to 1 to use zlib rather than console tool])
		 if test "x$with_zlib" = "xstatic"; then
			dpkg_zlib_libs="-Wl,-Bstatic -lz -Wl,-Bdynamic"
		 else
			dpkg_zlib_libs="-lz"
		 fi
		 ZLIB_LIBS="${ZLIB_LIBS:+$ZLIB_LIBS }$dpkg_zlib_libs"
		 with_zlib="yes"],
		[if test -n "$with_zlib"; then
			AC_MSG_FAILURE([zlib library not found])
		 fi])

	AC_CHECK_HEADER([zlib.h],,
		[if test -n "$with_zlib"; then
			AC_MSG_FAILURE([zlib header not found])
		 fi])
fi
])# DPKG_LIB_ZLIB

# DPKG_LIB_BZ2
# ------------
# Check for bz2 library.
AC_DEFUN([DPKG_LIB_BZ2],
[AC_ARG_VAR([BZ2_LIBS], [linker flags for bz2 library])dnl
AC_ARG_WITH(bz2,
	AS_HELP_STRING([--with-bz2],
		       [use bz2 library for compression and decompression]))
if test "x$with_bz2" != "xno"; then
	AC_CHECK_LIB([bz2], [BZ2_bzdopen],
		[AC_DEFINE(WITH_BZ2, 1,
			[Define to 1 to use libbz2 rather than console tool])
		 if test "x$with_bz2" = "xstatic"; then
			dpkg_bz2_libs="-Wl,-Bstatic -lbz2 -Wl,-Bdynamic"
		 else
			dpkg_bz2_libs="-lbz2"
		 fi
		 BZ2_LIBS="${BZ2_LIBS:+$BZ2_LIBS }$dpkg_bz2_libs"
		 with_bz2="yes"],
		[if test -n "$with_bz2"; then
			AC_MSG_FAILURE([bz2 library not found])
		 fi])

	AC_CHECK_HEADER([bzlib.h],,
		[if test -n "$with_bz2"; then
			AC_MSG_FAILURE([bz2 header not found])
		 fi])
fi
])# DPKG_LIB_BZ2

# DPKG_LIB_SELINUX
# ----------------
# Check for selinux library.
AC_DEFUN([DPKG_LIB_SELINUX],
[AC_ARG_VAR([SELINUX_LIBS], [linker flags for selinux library])dnl
AC_ARG_WITH(selinux,
	AS_HELP_STRING([--with-selinux],
		       [use selinux library to set security contexts]))
if test "x$with_selinux" != "xno"; then
	AC_CHECK_LIB([selinux], [is_selinux_enabled],
		[AC_DEFINE(WITH_SELINUX, 1,
			[Define to 1 to compile in SELinux supoprt])
		 if test "x$with_selinux" = "xstatic"; then
			dpkg_selinux_libs="-Wl,-Bstatic -lselinux -lsepol -Wl,-Bdynamic"
		 else
			dpkg_selinux_libs="-lselinux"
		 fi
		 SELINUX_LIBS="${SELINUX_LIBS:+$SELINUX_LIBS }$dpkg_selinux_libs"
		 with_selinux="yes"],
		[if test -n "$with_selinux"; then
			AC_MSG_FAILURE([selinux library not found])
		 fi])

	AC_CHECK_HEADER([selinux/selinux.h],,
		[if test -n "$with_selinux"; then
			AC_MSG_FAILURE([selinux header not found])
		 fi])
fi
])# DPKG_LIB_SELINUX

# DPKG_LIB_CURSES
# ---------------
# Check for curses library.
AC_DEFUN([DPKG_LIB_CURSES],
[AC_ARG_VAR([CURSES_LIBS], [linker flags for curses library])dnl
AC_CHECK_LIB([ncurses], [initscr], [CURSES_LIBS="${CURSES_LIBS:+$CURSES_LIBS }-lncurses"],
	[AC_CHECK_LIB([curses], [initscr], [CURSES_LIBS="${CURSES_LIBS:+$CURSES_LIBS }-lcurses"],
		[AC_MSG_WARN([no curses library found])])])
])# DPKG_LIB_CURSES

# DPKG_LIB_SSD
# ------------
# Check for start-stop-daemon libraries.
AC_DEFUN([DPKG_LIB_SSD],
[AC_ARG_VAR([SSD_LIBS], [linker flags for start-stop-daemon])dnl
AC_CHECK_LIB([ihash], [ihash_create], [SSD_LIBS="${SSD_LIBS:+$SSD_LIBS }-lihash"])
AC_CHECK_LIB([ps], [proc_stat_list_create], [SSD_LIBS="${SSD_LIBS:+$SSD_LIBS }-lps"])
AC_CHECK_LIB([shouldbeinlibc], [fmt_past_time], [SSD_LIBS="${SSD_LIBS:+$SSD_LIBS }-lshouldbeinlibc"])
AC_CHECK_LIB([kvm], [kvm_openfiles], [SSD_LIBS="${SSD_LIBS:+$SSD_LIBS }-lkvm"])
])# DPKG_LIB_SSD
