/*
 * libdpkg - Debian packaging suite library routines
 * myopt.h - declarations for my very own option parsing
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
 * License along with this file; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#ifndef MYOPT_H
#define MYOPT_H

typedef void (*voidfnp)(void);

struct cmdinfo {
  const char *olong;
  char oshort;
  int takesvalue; /* 0 = normal   1 = standard value   2 = option string cont */
  int *iassignto;
  const char **sassignto;
  void (*call)(const struct cmdinfo*, const char *value);
  int arg;
  void *parg;
  voidfnp farg;
};

void myfileopt(const char* fn, const struct cmdinfo* cmdinfos);
void myopt(const char *const **argvp, const struct cmdinfo *cmdinfos);
void loadcfgfile(const char *prog, const struct cmdinfo *cmdinfos);
#endif /* MYOPT_H */
