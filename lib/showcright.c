/*
 * libdpkg - Debian packaging suite library routines
 * showcright.c - show copyright file routine
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
#include <config.h>

#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>

#include <dpkg.h>

void showcopyright(const struct cmdinfo *c, const char *v) NONRETURNING;
void showcopyright(const struct cmdinfo *c, const char *v) {
  int fd;
  fd= open(COPYINGFILE,O_RDONLY);
  if (fd < 0) ohshite(_("cannot open GPL file "));
  fd_fd_copy(fd, 1, -1, "showcopyright");
  exit(0);
}
