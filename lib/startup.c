/*
 * dpkg - main program for package management
 * main.c - main program
 *
 * Copyright (C) 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 *
 * This is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2,
 * or (at your option) any later version.
 *
 * This is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with dpkg; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>
#include <unistd.h>
#include <dirent.h>
#include <limits.h>
#include <ctype.h>

#include <config.h>
#include <dpkg.h>
#include <dpkg-db.h>
#include <version.h>
#include <myopt.h>

void standard_startup(jmp_buf *ejbuf, int argc, const char *const **argv, const char *prog, int loadcfg, const struct cmdinfo cmdinfos[]) {

  setlocale(LC_ALL, "");
  bindtextdomain(PACKAGE, LOCALEDIR);
  textdomain(PACKAGE);

  if (setjmp(*ejbuf)) { /* expect warning about possible clobbering of argv */
    error_unwind(ehflag_bombout); exit(2);
  }
  push_error_handler(ejbuf,print_error_fatal,0);

  umask(022); /* Make sure all our status databases are readable. */
 
  if (loadcfg)
    loadcfgfile(prog, cmdinfos);

  myopt(argv,cmdinfos);
}

void standard_shutdown(void) {
  set_error_display(0,0);
  error_unwind(ehflag_normaltidy);
  nffreeall();
}
