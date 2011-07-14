/*
 * libdpkg - Debian packaging suite library routines
 * parsedump.h - declarations for in-core database reading/writing
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2001 Wichert Akkerman
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

#ifndef LIBDPKG_PARSEDUMP_H
#define LIBDPKG_PARSEDUMP_H

struct fieldinfo;

struct parsedb_state {
	enum parsedbflags flags;
	struct pkginfo *pkg;
	struct pkgbin *pkgbin;
	const char *filename;
	int lno;
};

#define PKGIFPOFF(f) (offsetof(struct pkgbin, f))
#define PKGPFIELD(pifp,of,type) (*(type*)((char*)(pifp)+(of)))

#define FILEFOFF(f) (offsetof(struct filedetails, f))
#define FILEFFIELD(filedetail,of,type) (*(type*)((char*)(filedetail)+(of)))

typedef void freadfunction(struct pkginfo *pigp, struct pkgbin *pifp,
                           struct parsedb_state *ps,
                           const char *value, const struct fieldinfo *fip);
freadfunction f_name, f_charfield, f_priority, f_section, f_status, f_filecharf;
freadfunction f_boolean, f_dependency, f_conffiles, f_version, f_revision;
freadfunction f_configversion;
freadfunction f_trigpend, f_trigaw;

enum fwriteflags {
	/* Print field header and trailing newline. */
	fw_printheader = 001,
};

typedef void fwritefunction(struct varbuf*,
                            const struct pkginfo *, const struct pkgbin *,
			    enum fwriteflags flags, const struct fieldinfo*);
fwritefunction w_name, w_charfield, w_priority, w_section, w_status, w_configversion;
fwritefunction w_version, w_null, w_booleandefno, w_dependency, w_conffiles;
fwritefunction w_filecharf;
fwritefunction w_trigpend, w_trigaw;

struct fieldinfo {
  const char *name;
  freadfunction *rcall;
  fwritefunction *wcall;
  size_t integer;
};

void parse_db_version(struct parsedb_state *ps,
                      struct versionrevision *version, const char *value,
                      const char *fmt, ...) DPKG_ATTR_PRINTF(4);

void parse_error(struct parsedb_state *ps, const char *fmt, ...)
	DPKG_ATTR_NORET DPKG_ATTR_PRINTF(2);
void parse_warn(struct parsedb_state *ps, const char *fmt, ...)
	DPKG_ATTR_PRINTF(2);
void parse_must_have_field(struct parsedb_state *ps,
                           const char *value, const char *what);
void parse_ensure_have_field(struct parsedb_state *ps,
                             const char **value, const char *what);

#define MSDOS_EOF_CHAR '\032' /* ^Z */

struct nickname {
  const char *nick;
  const char *canon;
};

extern const struct fieldinfo fieldinfos[];

#endif /* LIBDPKG_PARSEDUMP_H */
