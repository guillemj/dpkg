/*
 * dpkg-deb - construction and deconstruction of *.deb archives
 * dpkg-deb.h - external definitions for this program
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

#ifndef DPKG_DEB_H
#define DPKG_DEB_H

typedef void dofunction(const char *const *argv);
dofunction do_build NONRETURNING; 
dofunction do_contents, do_control, do_showinfo;
dofunction do_info, do_field, do_extract, do_vextract, do_fsystarfile;

extern int debugflag, nocheckflag, oldformatflag;
extern const struct cmdinfo *cipaction;
extern dofunction *action;

void extracthalf(const char *debar, const char *directory,
                 const char *taroption, int admininfo);

extern const char *compression;
extern const char* showformat;
extern enum compression_type compress_type;

#define DEBMAGIC     "!<arch>\ndebian-binary   "
#define ADMINMEMBER		"control.tar.gz  "
#define ADMINMEMBER_COMPAT	"control.tar.gz/ "
#define DATAMEMBER_GZ		"data.tar.gz     "
#define DATAMEMBER_COMPAT_GZ	"data.tar.gz/    "
#define DATAMEMBER_BZ2   	"data.tar.bz2    "
#define DATAMEMBER_COMPAT_BZ2  	"data.tar.bz2/   "
#define DATAMEMBER_CAT   	"data.tar        "
#define DATAMEMBER_COMPAT_CAT  	"data.tar/       "

#endif /* DPKG_DEB_H */
