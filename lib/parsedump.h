/*
 * libdpkg - Debian packaging suite library routines
 * parse.c - declarations for in-core database reading/writing
 *
 * Copyright (C) 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright (C) 2001 Wichert Akkerman
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

#ifndef DPKG_PARSEDUMP_H
#define DPKG_PARSEDUMP_H

struct fieldinfo;

#define PKGIFPOFF(f) ((char*)(&(((struct pkginfoperfile *)0x1000)->f)) - \
                      (char*)(struct pkginfoperfile *)0x1000)
#define PKGPFIELD(pifp,of,type) (*(type*)((char*)(pifp)+(of)))

#define FILEFOFF(f) ((char*)(&(((struct filedetails *)0x1000)->f)) - \
                     (char*)(struct filedetails *)0x1000)
#define FILEFFIELD(filedetail,of,type) (*(type*)((char*)(filedetail)+(of)))

typedef void freadfunction(struct pkginfo *pigp, struct pkginfoperfile *pifp,
                           enum parsedbflags flags,
                           const char *filename, int lno, FILE *warnto, int *warncount,
                           const char *value, const struct fieldinfo *fip);
freadfunction f_name, f_charfield, f_priority, f_section, f_status, f_filecharf;
freadfunction f_boolean, f_dependency, f_conffiles, f_version, f_revision;
freadfunction f_configversion;

enum fwriteflags {
	fw_printheader	= 001	/* print field header and trailing newline */
};

typedef void fwritefunction(struct varbuf*,
			    const struct pkginfo*, const struct pkginfoperfile*,
			    enum fwriteflags flags, const struct fieldinfo*);
fwritefunction w_name, w_charfield, w_priority, w_section, w_status, w_configversion;
fwritefunction w_version, w_null, w_booleandefno, w_dependency, w_conffiles;
fwritefunction w_filecharf;

struct fieldinfo {
  const char *name;
  freadfunction *rcall;
  fwritefunction *wcall;
  unsigned int integer;
};

void parseerr(FILE *file, const char *filename, int lno, FILE *warnto, int *warncount,
              const struct pkginfo *pigp, int warnonly,
              const char *fmt, ...) PRINTFFORMAT(8,9);
void parsemustfield(FILE *file, const char *filename, int lno,
                    FILE *warnto, int *warncount,
                    const struct pkginfo *pigp, int warnonly,
                    const char **value, const char *what);

#define MSDOS_EOF_CHAR '\032' /* ^Z */

struct nickname {
  const char *nick;
  const char *canon;
};

extern const struct fieldinfo fieldinfos[];
extern const struct nickname nicknames[];
extern const int nfields; /* = elements in fieldinfos, including the sentinels */

#endif /* DPKG_PARSEDUMP_H */
