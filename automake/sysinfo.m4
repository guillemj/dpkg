dnl Bunch of extra macros to make dpkg more portable
dnl Copyright (C) 1999 Wichert Akkerman <wakkerma@debian.org>
dnl
dnl This program is free software; you can redistribute it and/or modify
dnl it under the terms of the GNU General Public License as published by
dnl the Free Software Foundation; either version 2, or (at your option)
dnl any later version.
dnl
dnl This program is distributed in the hope that it will be useful,
dnl but WITHOUT ANY WARRANTY; without even the implied warranty of
dnl MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
dnl GNU General Public License for more details.
dnl
dnl You should have received a copy of the GNU General Public License
dnl along with this program; if not, write to the Free Software
dnl Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
dnl 02111-1307, USA.

AC_DEFUN(AC_HAVE_SYSINFO,
[AC_CACHE_CHECK(whether sysinfo is available,
 ac_cv_func_sysinfo,
[ AC_CHECK_FUNC(sysinfo,ac_cv_func_sysinfo=yes,ac_cv_func_sysinfo=no)])
if test "$ac_cv_func_sysinfo" = "yes" ; then
  AC_DEFINE(HAVE_SYSINFO)
fi
])

AC_DEFUN(AC_MEMINFO_IN_SYSINFO,
[AC_REQUIRE([AC_HAVE_SYSINFO])dnl
 if test "$ac_cv_header_sys_sysinfo" = "" ; then
   AC_CHECK_HEADERS(sys/sysinfo.h)
 fi
 AC_CACHE_CHECK(whether struct sysinfo contains memory information,
 ac_cv_meminfo_in_sysinfo,
[AC_TRY_COMPILE([
#ifdef HAVE_SYS_SYSINFO_H
#include <sys/sysinfo.h>
#endif
], [struct sysinfo si ; si.freeram;si.sharedram;si.bufferram;],
  ac_cv_meminfo_in_sysinfo=yes, ac_cv_meminfo_in_sysinfo=no)])
 if test "$ac_cv_have_sysinfo_meminfo" = yes ; then
   AC_DEFINE(MEMINFO_IN_SYSINFO)
 fi
])


