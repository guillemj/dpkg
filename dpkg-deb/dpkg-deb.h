/*
 * dpkg-deb - construction and deconstruction of *.deb archives
 * dpkg-deb.h - external definitions for this program
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

#ifndef DPKG_DEB_H
#define DPKG_DEB_H

action_func do_build;
action_func do_contents;
action_func do_control;
action_func do_showinfo;
action_func do_info;
action_func do_field;
action_func do_extract;
action_func do_vextract;
action_func do_raw_extract;
action_func do_fsystarfile;

extern int opt_verbose;
extern int debugflag, nocheckflag, oldformatflag;

void extracthalf(const char *debar, const char *dir,
                 const char *taroption, int admininfo);

extern const char* showformat;
extern struct compress_params compress_params;

#define ARCHIVEVERSION		"2.0"

#define BUILDCONTROLDIR		"DEBIAN"
#define EXTRACTCONTROLDIR	BUILDCONTROLDIR

/* Set BUILDOLDPKGFORMAT to 1 to build old-format archives by default. */
#ifndef BUILDOLDPKGFORMAT
#define BUILDOLDPKGFORMAT 0
#endif

#define OLDARCHIVEVERSION	"0.939000"

#define OLDDEBDIR		"DEBIAN"
#define OLDOLDDEBDIR		".DEBIAN"

#define DEBMAGIC		"debian-binary"
#define ADMINMEMBER		"control.tar.gz"
#define DATAMEMBER		"data.tar"

#define MAXFILENAME 2048
#define MAXFIELDNAME 200

#ifdef PATH_MAX
# define INTERPRETER_MAX PATH_MAX
#else
# define INTERPRETER_MAX 1024
#endif

#endif /* DPKG_DEB_H */
