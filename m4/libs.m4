# DPKG_LIB_ZLIB
# -------------
# Check for zlib library.
AC_DEFUN([DPKG_LIB_ZLIB],
[AC_ARG_VAR([ZLIB_CFLAGS], [compiler flags for zlib library])dnl
AC_ARG_VAR([ZLIB_LIBS], [linker flags for zlib library])dnl
AC_ARG_WITH(zlib,
	AS_HELP_STRING([--with-zlib],
		       [use zlib for compression and decompression (yes/static)]),
[case "$with_zlib" in
    yes)
	ZLIB_CFLAGS="${ZLIB_CFLAGS:+$ZLIB_CFLAGS }-DWITH_ZLIB"
	ZLIB_LIBS="${ZLIB_LIBS:+$ZLIB_LIBS }-lz"
	;;
    static)
	ZLIB_CFLAGS="${ZLIB_CFLAGS:+$ZLIB_CFLAGS }-DWITH_ZLIB"
	ZLIB_LIBS="${ZLIB_LIBS:+$ZLIB_LIBS }-Wl,-Bstatic -lz -Wl,-Bdynamic"
	;;
esac])
])# DPKG_LIB_ZLIB

# DPKG_LIB_BZ2
# ------------
# Check for bz2 library.
AC_DEFUN([DPKG_LIB_BZ2],
[AC_ARG_VAR([BZ2_CFLAGS], [compiler flags for bz2 library])dnl
AC_ARG_VAR([BZ2_LIBS], [linker flags for bz2 library])dnl
AC_ARG_WITH(bz2,
	AS_HELP_STRING([--with-bz2],
		       [use bz2 library for compression and decompression (yes/static)]),
[case "$with_bz2" in
    yes)
	BZ2_CFLAGS="${BZ2_CFLAGS:+$BZ2_CFLAGS }-DWITH_BZ2"
	BZ2_LIBS="${BZ2_LIBS:+$BZ2_LIBS }-lbz2"
	;;
    static)
	BZ2_CFLAGS="${BZ2_CFLAGS:+$BZ2_CFLAGS }-DWITH_BZ2"
	BZ2_LIBS="${BZ2_LIBS:+$BZ2_LIBS }-Wl,-Bstatic -lbz2 -Wl,-Bdynamic"
	;;
esac])
])# DPKG_LIB_BZ2

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
