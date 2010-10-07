/*
 * libdpkg - Debian packaging suite library routines
 * myopt.h - declarations for my very own option parsing
 *
 * Copyright © 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 *
 * This is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef MYOPT_H
#define MYOPT_H

#include <dpkg/macros.h>

DPKG_BEGIN_DECLS

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

extern const char printforhelp[];

void badusage(const char *fmt, ...) DPKG_ATTR_NORET DPKG_ATTR_PRINTF(1);

#define MAX_CONFIG_LINE 1024

void myfileopt(const char* fn, const struct cmdinfo* cmdinfos);
void myopt(const char *const **argvp, const struct cmdinfo *cmdinfos);
void loadcfgfile(const char *prog, const struct cmdinfo *cmdinfos);

/**
 * Current cmdinfo action.
 */
extern const struct cmdinfo *cipaction;

void setaction(const struct cmdinfo *cip, const char *value);
void setobsolete(const struct cmdinfo *cip, const char *value);

#define ACTION(longopt, shortopt, code, function) \
 { longopt, shortopt, 0, NULL, NULL, setaction, code, NULL, (voidfnp)function }
#define OBSOLETE(longopt, shortopt) \
 { longopt, shortopt, 0, NULL, NULL, setobsolete, 0, NULL, NULL }

DPKG_END_DECLS

#endif /* MYOPT_H */
