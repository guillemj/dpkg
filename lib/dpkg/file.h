/*
 * libdpkg - Debian packaging suite library routines
 * file.h - file handling routines
 *
 * Copyright © 2008 Guillem Jover <guillem@debian.org>
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

#ifndef DPKG_FILE_H
#define DPKG_FILE_H

#include <dpkg/macros.h>

DPKG_BEGIN_DECLS

/*
 * Copy file ownership and permissions from one file to another.
 */
void file_copy_perms(const char *src, const char *dst);

DPKG_END_DECLS

#endif /* DPKG_FILE_H */

