/*
 * libdpkg - Debian packaging suite library routines
 * tarfn.h - tar archive extraction functions
 *
 * Copyright © 1995 Bruce Perens
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

#ifndef LIBDPKG_TARFN_H
#define LIBDPKG_TARFN_H

#include <sys/types.h>

#include <unistd.h>
#include <stdlib.h>

#define TARBLKSZ	512

enum tar_format {
	tar_format_old,
	tar_format_gnu,
	tar_format_ustar,
	tar_format_pax,
};

enum tar_filetype {
	tar_filetype_file0 = '\0',	/* For compatibility with decades-old bug */
	tar_filetype_file = '0',
	tar_filetype_hardlink = '1',
	tar_filetype_symlink = '2',
	tar_filetype_chardev = '3',
	tar_filetype_blockdev = '4',
	tar_filetype_dir = '5',
	tar_filetype_fifo = '6',
	tar_filetype_gnu_longlink = 'K',
	tar_filetype_gnu_longname = 'L',
};

struct	TarInfo {
	enum tar_format format;	/* Tar archive format. */
	enum tar_filetype type;	/* Regular, Directory, Special, Link */
	char *name;		/* File name */
	char *linkname;		/* Name for symbolic and hard links */
	size_t size;		/* Size of file */
	time_t mtime;		/* Last-modified time */
	mode_t mode;		/* Unix mode, including device bits. */
	uid_t uid;		/* Numeric UID */
	gid_t gid;		/* Numeric GID */
	dev_t dev;		/* Special device for mknod() */
};

typedef int (*tar_read_func)(void *ctx, char *buffer, int length);
typedef int (*tar_func)(void *ctx, struct TarInfo *h);

struct tar_operations {
	tar_read_func read;

	tar_func extract_file;
	tar_func link;
	tar_func symlink;
	tar_func mkdir;
	tar_func mknod;
};

int TarExtractor(void *ctx, const struct tar_operations *ops);

#endif
